# iconvcr — Implementation Plan

A pure Crystal clone of GNU libiconv, tested against libiconv for correctness.

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed data structure diagrams.

## Architecture

libiconv's design: **every encoding converts through UCS-4 (Unicode) as a pivot**.

```
Source bytes → UCS-4 codepoint → Target bytes
  decode()                        encode()
```

### What Actually Matters for Performance

The conversion loop is the entire program. Everything else is setup cost paid once.
The loop does two things per character: decode a byte sequence into a codepoint,
encode that codepoint into the target byte sequence. That's it.

The question is: how do we make that loop fast?

**Answer: don't run it.**

The fastest code is code that doesn't execute. Most real-world text is ASCII. Most
real-world conversions are between ASCII-superset encodings. For those conversions,
every ASCII byte maps to itself. So the actual architecture is:

```
1. Scan forward for the longest run of bytes < 0x80
2. memcpy that run directly to output (both encodings agree on ASCII)
3. Hit a non-ASCII byte? NOW decode→pivot→encode just that character
4. Go back to step 1
```

This is not an "optimization" bolted on later. This IS the converter. The
character-at-a-time pivot loop is the fallback for the non-ASCII minority of bytes.

For the ~10 encodings that are NOT ASCII supersets (EBCDIC, UTF-16, UTF-32, UTF-7),
you run the character-at-a-time loop. That's fine. Nobody is converting terabytes
of EBCDIC.

### Dispatch: Switch on an Enum, Not Proc Pointers

A Crystal Proc is a closure — pointer + context, heap-allocated environment capture.
Even without captures, calling through a Proc is an indirect call that the branch
predictor has to learn and that LLVM cannot inline through.

A `case` statement on an enum compiles to a jump table. After the first iteration,
the branch predictor nails it every time (it's the same encoding for the whole
conversion). And LLVM *can* inline through a case statement — if the encoding is
known at compile time or if profile-guided optimization is used.

```crystal
enum EncodingID : UInt16
  ASCII
  UTF8
  ISO_8859_1
  ISO_8859_2
  # ... every encoding gets an ID
  SHIFT_JIS
  EUC_JP
  GB18030
  # ...
end

struct Codec
  getter id : EncodingID
  getter ascii_superset : Bool
  getter max_bytes_per_char : UInt8
end
```

The converter stores two `EncodingID` values and switches on them:

```crystal
@[AlwaysInline]
private def decode_one(src : Bytes, pos : Int32) : DecodeResult
  case @from_id
  when .ascii?      then Decode.ascii(src, pos)
  when .utf8?       then Decode.utf8(src, pos)
  when .iso_8859_1? then Decode.iso_8859_1(src, pos)
  when .shift_jis?  then Decode.shift_jis(src, pos)
  # ... etc
  else                   Decode.single_byte(src, pos, @from_table)
  end
end
```

For the ~50 single-byte encodings that are all table lookups, the `else` branch
handles them all with one function and a pointer to the right table. The switch
only has explicit branches for encodings with unique decode logic.

### Data Layout: Think About What Actually Gets Touched

**Single-byte decode table:** `StaticArray(UInt16, 256)` = 512 bytes. Direct index.
Every single-byte encoding uses the exact same decode function, just different
table data. One function, not 50.

**Single-byte encode table:** Don't binary search. Use a flat `StaticArray(UInt8, 65536)`
= 64KB. Direct index by codepoint. Zero value means "not representable." 64KB fits
comfortably in L2, and after the first few accesses the hot entries are in L1.
Binary search does 8 unpredictable branches per character. Direct index does zero.
64KB per encoding × 50 encodings = 3.2MB total. That's nothing.

BUT — you don't load all 50 into memory. You load the two you're actually using.
So it's 128KB for both tables. That's L2.

**CJK decode table:** Direct 2D array. `table[lead - offset][trail - offset]`.
O(1), no branches.

**CJK encode table:** Two-level page table like libiconv. O(1), two loads. Fine.

### Result Types

```crystal
struct DecodeResult
  getter codepoint : UInt32  # The UCS-4 value
  getter status : Int32      # >0 = bytes consumed, 0 = need more, -1 = invalid
end

struct EncodeResult
  getter status : Int32  # >0 = bytes written, 0 = buffer full, -1 = unencodable
end
```

Stack-allocated. 8 bytes and 4 bytes. No union types. No heap.

### The Actual Conversion Loop

```crystal
def convert(src : Bytes, dst : Bytes) : {Int32, Int32}
  src_pos = 0
  dst_pos = 0

  # Are both encodings ASCII supersets? If so, use the fast scanner.
  if @from_ascii_superset && @to_ascii_superset
    while src_pos < src.size
      # --- FAST PATH: scan for ASCII run ---
      ascii_end = scan_ascii_run(src, src_pos)
      if ascii_end > src_pos
        len = ascii_end - src_pos
        return {src_pos, dst_pos} if dst_pos + len > dst.size  # output full
        src.copy_to(dst + dst_pos, len, src_pos)  # memcpy
        src_pos = ascii_end
        dst_pos += len
      end

      break if src_pos >= src.size

      # --- SLOW PATH: one non-ASCII character ---
      dr = decode_one(src, src_pos)
      return handle_decode_error(src_pos, dst_pos) unless dr.status > 0
      er = encode_one(dr.codepoint, dst, dst_pos)
      return handle_encode_error(dr, src_pos, dst_pos) unless er.status > 0
      src_pos += dr.status
      dst_pos += er.status
    end
  else
    # Non-ASCII-superset encodings: character at a time, no fast path
    while src_pos < src.size
      dr = decode_one(src, src_pos)
      return handle_decode_error(src_pos, dst_pos) unless dr.status > 0
      er = encode_one(dr.codepoint, dst, dst_pos)
      return handle_encode_error(dr, src_pos, dst_pos) unless er.status > 0
      src_pos += dr.status
      dst_pos += er.status
    end
  end

  {src_pos, dst_pos}
end
```

`scan_ascii_run` is where the real throughput comes from:

```crystal
@[AlwaysInline]
private def scan_ascii_run(src : Bytes, from : Int32) : Int32
  pos = from
  # Process 8 bytes at a time: load as UInt64, check if any byte has high bit set
  while pos + 8 <= src.size
    word = (src.to_unsafe + pos).as(Pointer(UInt64)).value
    break if word & 0x8080808080808080_u64 != 0
    pos += 8
  end
  # Finish remaining bytes
  while pos < src.size && src.to_unsafe[pos] < 0x80
    pos += 1
  end
  pos
end
```

That's 1 comparison per 8 bytes for ASCII text. On a 3GHz machine doing one
comparison per cycle, that's 24 GB/s theoretical throughput for the scanning
alone. The memcpy after it runs at memory bandwidth.

### Buffer Management

**Do not use "typical" expansion factors. Use worst-case.**

If you allocate based on "typical" and the input is adversarial, you reallocate and
copy in the middle of conversion. That's a performance cliff. Allocate for worst case:

```
Worst-case expansion:
  → UTF-8:    input.size × 3   (every byte could become a 3-byte UTF-8 sequence)
  → UTF-16:   input.size × 2   (every byte becomes 2 bytes)
  → UTF-32:   input.size × 4   (every byte becomes 4 bytes)
  → single-byte: input.size × 1 (1:1 or shorter)
```

For the streaming API, the USER provides the buffer. You don't allocate at all.
You fill what they gave you, return how much you consumed and produced, and they
call you again. Zero allocations in the hot path.

For the one-shot API, allocate worst-case, convert, then shrink (or return a slice).
One allocation total.

### Error Handling Modes

Same as libiconv:

| Mode | On ILSEQ (bad input) | On ILUNI (can't encode) |
|------|---------------------|------------------------|
| Default | Return error, stop | Return error, stop |
| `//IGNORE` | Skip bad byte, continue | Skip character, continue |
| `//TRANSLIT` | Return error, stop | Try transliteration, then error |
| `//TRANSLIT//IGNORE` | Skip bad byte | Try translit, then skip |

### Thread Safety

`Converter` holds mutable state (position in stateful codecs). One per fiber.
Everything else is immutable compile-time data. Nothing to think about.

## File Structure

Don't create 100 files for what is fundamentally DATA + a few functions.

```
iconvcr/
├── shard.yml
├── src/
│   ├── iconvcr.cr                     # Public API: Iconvcr.convert, Converter class
│   └── iconvcr/
│       ├── types.cr                   # DecodeResult, EncodeResult, CodecState, EncodingID
│       ├── converter.cr               # Converter class + conversion loop + fast scanner
│       ├── registry.cr                # Name normalization + lookup → EncodingID
│       ├── decode.cr                  # All decode functions (switch dispatch)
│       ├── encode.cr                  # All encode functions (switch dispatch)
│       ├── transliteration.cr         # //TRANSLIT fallbacks
│       ├── tables/
│       │   ├── single_byte.cr         # ALL single-byte tables in one file (~50 tables)
│       │   ├── cjk_jis.cr            # JIS X 0208, 0212, 0201 tables
│       │   ├── cjk_gb.cr             # GB2312, GBK, GB18030 tables
│       │   ├── cjk_big5.cr           # Big5, CNS 11643 tables
│       │   ├── cjk_ksc.cr            # KSC 5601 tables
│       │   └── ebcdic.cr             # All EBCDIC tables in one file
│       └── codecs/                    # Only for encodings with UNIQUE LOGIC
│           ├── utf8.cr                # Non-trivial: variable-length, validation
│           ├── utf16.cr               # BOM handling, surrogate pairs
│           ├── utf32.cr               # BOM handling, byte order
│           ├── utf7.cr                # Stateful, base64
│           ├── gb18030.cr             # Algorithmic 4-byte ranges
│           ├── iso2022_jp.cr          # Stateful escape sequences
│           ├── iso2022_cn.cr          # Stateful
│           ├── iso2022_kr.cr          # Stateful
│           └── hz.cr                  # Stateful ~{...~} framing
├── tools/
│   ├── generate_tables.cr             # ONE generator. Reads .TXT, outputs Crystal.
│   └── fetch_mappings.sh              # Downloads source .TXT files
├── spec/
│   ├── spec_helper.cr
│   ├── converter_spec.cr              # Core loop tests
│   ├── encode_decode_spec.cr          # Per-encoding correctness
│   ├── comparison_spec.cr             # System iconv FFI comparison
│   ├── exhaustive_spec.cr             # Every byte/codepoint for table-driven
│   ├── fuzz_spec.cr                   # Random input comparison
│   ├── bench_spec.cr                  # Throughput benchmarks (run with flag)
│   └── fixtures/                      # .TXT mapping files
└── LICENSE
```

**~20 source files, not 100+.** Tables are data — they go in data files,
not one-file-per-encoding. Codecs only get their own file if they have
unique logic (stateful, algorithmic ranges, BOM handling). The 50 single-byte
encodings share one decode function and one encode function. They're not
50 separate things — they're one thing with 50 different tables.

## Public API

```crystal
module Iconvcr
  VERSION = "0.1.0"

  # One-shot: allocates output, returns it
  def self.convert(input : Bytes, from : String, to : String) : Bytes
  def self.convert(input : String, from : String, to : String) : Bytes

  # Handle-based: reusable, streaming
  class Converter
    def initialize(from : String, to : String)

    # Streaming: converts what fits, returns {bytes_consumed, bytes_written}
    # Call repeatedly until input is exhausted.
    def convert(input : Bytes, output : Bytes) : {Int32, Int32}

    # IO streaming: reads from input, writes to output
    def convert(input : IO, output : IO, buffer_size : Int32 = 8192)

    # One-shot convenience (allocates)
    def convert(input : Bytes) : Bytes

    def reset   # Reset stateful codec state
  end

  def self.encoding_supported?(name : String) : Bool
  def self.list_encodings : Array(String)
end
```

## Implementation Phases

### Phase 1: Working Converter + Benchmarks (4 days)

Build the entire pipeline end to end for 3 encodings. Including benchmarks.
If you can't measure it, you can't know if your design works.

- `types.cr` — DecodeResult, EncodeResult, CodecState, EncodingID enum (start small)
- `converter.cr` — the conversion loop with ASCII fast scanner from day one
- `decode.cr` / `encode.cr` — ASCII, UTF-8, ISO-8859-1
- `registry.cr` — name lookup (just a hash for now)
- `iconvcr.cr` — public API
- `spec/converter_spec.cr` — correctness tests
- `spec/comparison_spec.cr` — FFI to system iconv, compare output
- `spec/bench_spec.cr` — throughput measurement

**Exit criteria:** UTF-8→ISO-8859-1 conversion works correctly and we have MB/s numbers
to compare against system iconv. We know if the design is viable.

### Phase 2: All Single-Byte Encodings (3 days)

- `tools/generate_tables.cr` — reads .TXT files, generates Crystal source
- `tables/single_byte.cr` — all ~50 tables (one file, just data)
- Wire into the decode/encode switch: single `else` branch handles all of them
- `spec/exhaustive_spec.cr` — test every byte value for every encoding against system iconv

**Exit criteria:** 53 encodings work. Exhaustive correctness for all of them.

### Phase 3: Unicode Family (3 days)

- `codecs/utf16.cr` — UTF-16BE, UTF-16LE, UTF-16 (BOM-detecting)
- `codecs/utf32.cr` — UTF-32BE, UTF-32LE, UTF-32 (BOM-detecting)
- UCS-2, UCS-4 variants (thin wrappers)
- `codecs/utf7.cr` — first stateful encoding, validates the state design
- C99, Java escape notations (trivial)

**Exit criteria:** All Unicode family encodings work. UTF-7 state machine works correctly.

### Phase 4: CJK (8 days)

The big one. Mostly table generation + wiring.

- `tools/generate_tables.cr` — extend for CJK (2D tables, page tables)
- `tables/cjk_*.cr` — character set tables
- `codecs/gb18030.cr` — algorithmic 4-byte ranges need custom logic
- `codecs/iso2022_jp.cr`, `iso2022_cn.cr`, `iso2022_kr.cr`, `hz.cr` — stateful
- EUC-JP, Shift_JIS, EUC-KR, Big5, GBK, CP932, CP949, CP950 etc.
- All stateless CJK encodings use the generic decode/encode with different tables

**Exit criteria:** All ~30 CJK encodings work. Fuzz-tested against system iconv.

### Phase 5: Everything Else (3 days)

- `tables/ebcdic.cr` — all EBCDIC variants (same table approach)
- DOS codepages, AIX codepages, misc encodings
- These are all table-driven, same as single-byte but some are multi-byte

### Phase 6: Transliteration + Polish (3 days)

- `transliteration.cr` — fallback tables
- `//TRANSLIT` and `//IGNORE` suffix parsing
- Full alias table (port from libiconv)
- Complete fuzz test suite across all encoding pairs

**Total: ~24 days, ~150+ encodings**

## Testing Strategy

### 1. Exhaustive Table Tests (primary method)

For every table-driven encoding, test EVERY input byte value (0x00-0xFF for single-byte,
all valid lead+trail pairs for multibyte) against system iconv via FFI. This is not
sampling — it's proving correctness for every possible input.

For encode, test every BMP codepoint (0x0000-0xFFFF) against system iconv.

This is feasible: 65536 codepoints × ~150 encodings = ~10M conversions. Takes seconds.

### 2. Fuzz Testing

Random byte sequences of random lengths, fed to both system iconv and iconvcr,
compare outputs AND error behavior. Run for every encoding pair that makes sense.

### 3. Edge Cases

- Empty input
- Truncated multibyte sequences
- BOM handling
- State reset (stateful encodings)
- Buffer boundary splits in streaming mode
- Every documented error condition

### 4. Performance Tests

Throughput in MB/s for representative encoding pairs. Run as part of CI with
regression detection. Not a separate phase — built from day one.

## Performance Targets

| Operation | Target | How |
|-----------|--------|-----|
| UTF-8 → UTF-8 | >4 GB/s | memcpy + validate (8-byte word scan) |
| ASCII text through any ASCII-superset pair | >4 GB/s | 8-byte word scan + memcpy |
| ISO-8859-1 → UTF-8 | >1 GB/s | Direct compute, no table |
| Single-byte → UTF-8 | >500 MB/s | Table lookup + UTF-8 emit |
| EUC-JP → UTF-8 | >200 MB/s | 2D table lookup |
| GB18030 → UTF-8 | >100 MB/s | Mixed table + algorithmic |
| vs system iconv | ≥100% | We should match or beat C on common cases |

The "≥80% of system iconv" target from before was wrong. If you're processing
8 bytes of ASCII at a time and the C implementation is doing it one byte at a time,
you should be *faster*. Set the bar where it should be.

## Key Risks

| Risk | Mitigation |
|------|------------|
| CJK table accuracy | Use exact same .TXT source files. Exhaustive comparison test. |
| GB18030 4-byte ranges | Port libiconv logic line by line. Test every BMP codepoint. |
| Crystal Proc overhead | Don't use Procs. Use enum switch. Verify with `--emit llvm-ir`. |
| Hidden heap allocations | Struct-only results. Check IR. Benchmark to catch regressions. |
| scan_ascii_run correctness | Unaligned reads need care. Test at every alignment offset. |
| LLVM not inlining decode/encode | Use `@[AlwaysInline]` on hot functions. Check IR. |
