# iconvcr — Architecture (Performance-First)

## The Core Insight

The previous architecture made a classic mistake: it designed the abstraction layer
first and hoped performance would follow. That's backwards. You look at the data,
figure out what the machine actually needs to do, and write the code that does that.
Then you see if you need abstractions at all.

Here's what character encoding conversion actually is, at the hardware level:

**It's a table lookup with memcpy.**

For ~90% of real-world text (ASCII), both the source and target encoding agree on the
mapping. The conversion is a no-op. You're copying bytes. For the remaining ~10%
(non-ASCII), you do one or two table lookups per character. That's it. There is no
complex algorithm here. There's data movement and table lookups.

So the architecture follows from the data:

```
1. Move bytes that don't need conversion (ASCII) as fast as possible
2. Look up bytes that do need conversion as fast as possible
3. Don't do anything else
```

## What the Previous Design Got Wrong

### 1. Proc Pointers Are Still Indirect Calls

The previous plan replaced abstract class vtables with Crystal `Proc` pointers and
declared victory. But a Proc in Crystal is a closure (function pointer + context
pointer). Calling through it is an indirect `call` instruction. The CPU's branch
predictor can learn indirect targets, but:

- It takes a few iterations to warm up
- LLVM **cannot** inline through a Proc call — the compiler sees an opaque function pointer
- Each Proc call has ABI overhead (save/restore registers, set up call frame)

Compare to a `case` statement on an enum: it compiles to a jump table (one indexed
branch), LLVM can see all the branch targets, and if the enum value is constant
(which it is for the lifetime of a Converter), LLVM can specialize.

### 2. One Character at a Time Is the Wrong Granularity

The previous conversion loop was:
```
while bytes left:
  decode one character → codepoint
  encode codepoint → output bytes
```

This processes the input one character at a time. For a 1MB file of English text,
that's ~1 million iterations of the loop, ~1 million decode calls, ~1 million
encode calls. Each call has overhead: bounds check the offset, read the byte,
check if it's an error, return a struct.

The right approach is to process in **runs**:
```
while bytes left:
  find the longest run of bytes that can be bulk-copied (ASCII)
  memcpy that run
  decode/encode the one non-ASCII character that ended the run
```

For English text, the "find the longest run" check processes 8 bytes per iteration
(one 64-bit load + one AND + one compare). The memcpy after it runs at memory
bandwidth. The per-character path only runs for the occasional accented character.

### 3. 50 Files for 50 Tables Is Organizational Overhead, Not Engineering

ISO-8859-2 and ISO-8859-15 differ only in their lookup table data. They use the
exact same decode function and the exact same encode function. Creating separate
files, modules, and registry entries for each one is not "good organization" — it's
creating work for the compiler, the file system, and the developer, with zero
benefit.

One file holds all single-byte tables. One function decodes any single-byte encoding
given a pointer to its table. One function encodes. Done.

### 4. Binary Search for Single-Byte Encode Is Pointlessly Slow

The previous plan used a sorted array with binary search for the reverse mapping
(codepoint → byte). 8 comparisons per character, each one an unpredictable branch.

A direct lookup array — `StaticArray(UInt8, 65536)` — is 64KB. Zero branches.
One indexed load. The active working set of codepoints fits in L1/L2 after a
few characters. 64KB per encoding is nothing — you only load two encodings at a time
(source and target), so it's 128KB total. L2 cache is typically 256KB-1MB per core.

### 5. "Typical" Buffer Expansion Factors Are Bugs

The previous plan sized output buffers using "typical" expansion ratios:
`CJK→UTF-8 → 1.5`. This means if you have CJK text where every character
is a 3-byte UTF-8 sequence from a 2-byte CJK encoding, you overflow the buffer
and have to reallocate mid-conversion.

Use worst case or accept reallocation. Don't pretend "typical" is safe.

## Revised Architecture

### Data Types

```crystal
# 8 bytes. Stack allocated. No union. No heap.
struct DecodeResult
  # codepoint: the UCS-4 value (only valid if status > 0)
  # status: >0 = bytes consumed, 0 = need more input, -1 = invalid sequence
  getter codepoint : UInt32
  getter status : Int32
end

# 4 bytes. Stack allocated.
struct EncodeResult
  # status: >0 = bytes written, 0 = output full, -1 = unencodable
  getter status : Int32
end

# Encoding identity — an enum, not a string, not a Proc
enum EncodingID : UInt16
  ASCII
  UTF8
  ISO_8859_1
  ISO_8859_2
  # ... all encodings
  SHIFT_JIS
  EUC_JP
  GB18030
  # ...
end

# Metadata about an encoding, queried once at Converter creation
struct EncodingInfo
  getter id : EncodingID
  getter ascii_superset : Bool       # Can we use the ASCII fast scanner?
  getter max_bytes_per_char : UInt8  # For worst-case buffer sizing
  getter stateful : Bool             # Needs CodecState?
end

# State for stateful codecs. 8 bytes. Stack allocated in Converter.
struct CodecState
  property mode : UInt8 = 0
  property flags : UInt8 = 0
  property buffer : UInt32 = 0
  property count : UInt8 = 0
end
```

### Dispatch

```crystal
class Converter
  @from : EncodingInfo
  @to : EncodingInfo
  @state_decode : CodecState
  @state_encode : CodecState

  # The hot functions. @[AlwaysInline] tells LLVM to inline at call site.
  # The case statement compiles to a jump table. After one iteration, the
  # branch predictor knows which case is hot and predicts perfectly.

  @[AlwaysInline]
  private def decode_one(src : Bytes, pos : Int32) : DecodeResult
    case @from.id
    when .ascii?       then Decode.ascii(src, pos)
    when .utf8?        then Decode.utf8(src, pos)
    when .iso_8859_1?  then Decode.iso_8859_1(src, pos)
    when .utf16_be?    then Decode.utf16_be(src, pos)
    when .utf16_le?    then Decode.utf16_le(src, pos)
    when .shift_jis?   then Decode.shift_jis(src, pos)
    when .euc_jp?      then Decode.euc_jp(src, pos)
    when .gb18030?     then Decode.gb18030(src, pos)
    when .iso2022_jp?  then Decode.iso2022_jp(src, pos, pointerof(@state_decode))
    # ... explicit branches only for encodings with unique logic
    else
      # Everything else is table-driven single-byte or CJK
      Decode.table_driven(src, pos, @from.id)
    end
  end

  @[AlwaysInline]
  private def encode_one(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    case @to.id
    when .ascii?       then Encode.ascii(cp, dst, pos)
    when .utf8?        then Encode.utf8(cp, dst, pos)
    when .iso_8859_1?  then Encode.iso_8859_1(cp, dst, pos)
    # ... same pattern
    else
      Encode.table_driven(cp, dst, pos, @to.id)
    end
  end
end
```

### The Conversion Loop

Two versions. One with the ASCII fast scanner (used when both encodings are ASCII
supersets). One without (for EBCDIC, UTF-16, UTF-32, UTF-7).

```crystal
def convert(src : Bytes, dst : Bytes) : {Int32, Int32}
  if @from.ascii_superset && @to.ascii_superset
    convert_ascii_fast(src, dst)
  else
    convert_general(src, dst)
  end
end

private def convert_ascii_fast(src : Bytes, dst : Bytes) : {Int32, Int32}
  src_pos = 0
  dst_pos = 0
  src_end = src.size
  dst_end = dst.size

  while src_pos < src_end
    # Scan for ASCII run: 8 bytes at a time using word-at-a-time comparison
    run_end = src_pos
    while run_end + 8 <= src_end
      word = (src.to_unsafe + run_end).as(Pointer(UInt64)).value
      break if word & 0x8080808080808080_u64 != 0
      run_end += 8
    end
    while run_end < src_end && src.to_unsafe[run_end] < 0x80
      run_end += 1
    end

    # Copy ASCII run
    run_len = run_end - src_pos
    if run_len > 0
      avail = dst_end - dst_pos
      copy_len = run_len < avail ? run_len : avail
      (src.to_unsafe + src_pos).copy_to(dst.to_unsafe + dst_pos, copy_len)
      src_pos += copy_len
      dst_pos += copy_len
      next if copy_len < run_len  # output full
    end

    break if src_pos >= src_end

    # Decode/encode one non-ASCII character
    dr = decode_one(src, src_pos)
    return {src_pos, dst_pos} if dr.status <= 0  # error
    er = encode_one(dr.codepoint, dst, dst_pos)
    return {src_pos, dst_pos} if er.status <= 0  # error
    src_pos += dr.status
    dst_pos += er.status
  end

  {src_pos, dst_pos}
end

private def convert_general(src : Bytes, dst : Bytes) : {Int32, Int32}
  src_pos = 0
  dst_pos = 0
  while src_pos < src.size
    dr = decode_one(src, src_pos)
    return {src_pos, dst_pos} if dr.status <= 0
    er = encode_one(dr.codepoint, dst, dst_pos)
    return {src_pos, dst_pos} if er.status <= 0
    src_pos += dr.status
    dst_pos += er.status
  end
  {src_pos, dst_pos}
end
```

### ASCII Scanner: Why 8 Bytes at a Time

```
Consider converting 1MB of English text (UTF-8 → ISO-8859-1):

Character-at-a-time:
  1,000,000 iterations
  1,000,000 decode calls (bounds check, read byte, check < 0x80, return struct)
  1,000,000 encode calls (bounds check, check codepoint range, write byte, return struct)
  = ~2,000,000 function calls with ~10 instructions each
  = ~20,000,000 instructions

Word-at-a-time ASCII scan + memcpy:
  125,000 word loads (1MB / 8 bytes)
  125,000 AND + compare operations
  1 memcpy of 1MB (runs at memory bandwidth)
  = ~250,000 instructions + memcpy

That's 80x fewer instructions. This is not a micro-optimization.
This is the difference between the program being fast and being slow.
```

### Table Layout

#### Single-Byte

```
Decode: decode_tables[encoding_id] → Pointer(StaticArray(UInt16, 256))
  - 512 bytes per encoding
  - Direct index by input byte value
  - 0xFFFF means "undefined / illegal"
  - Fits in L1 cache

Encode: encode_tables[encoding_id] → Pointer(StaticArray(UInt8, 65536))
  - 64KB per encoding
  - Direct index by Unicode codepoint (BMP only)
  - 0x00 means "undefined" (except for codepoint 0x0000 which maps to 0x00 in all encodings)
  - Fits in L2 cache
  - You load at most 2 of these (from + to), so 128KB working set

Total for 50 single-byte encodings:
  Decode: 50 × 512B = 25KB (trivial)
  Encode: 50 × 64KB = 3.2MB (loaded lazily, only 2 active at a time)
```

#### CJK

```
Decode: 2D array indexed by (lead_byte - offset, trail_byte - offset)
  - JIS X 0208: 94 × 94 × 2 bytes = ~17KB
  - GBK: 126 × 190 × 2 bytes = ~47KB
  - Big5: 89 × 157 × 2 bytes = ~27KB
  - O(1) lookup, sequential access pattern (cache-friendly)

Encode: Two-level page table (same as libiconv)
  - Level 1: summary[codepoint >> 8] → page index (256 bytes)
  - Level 2: detail[page_index][codepoint & 0xFF] → encoded bytes
  - O(1), two loads
  - ~20KB per charset

Total for CJK: ~300KB for all charsets combined
```

### What Gets Its Own File and Why

A file exists because it contains **unique logic**, not because it contains a
different encoding name.

| File | Why it exists |
|------|--------------|
| `converter.cr` | The conversion loop, ASCII scanner, buffer management |
| `decode.cr` | The decode dispatch switch + all non-trivial decode functions |
| `encode.cr` | The encode dispatch switch + all non-trivial encode functions |
| `registry.cr` | Name normalization, alias resolution → EncodingID |
| `types.cr` | Result structs, EncodingID enum, CodecState |
| `tables/single_byte.cr` | All 50 single-byte tables. It's data. One file. |
| `tables/cjk_jis.cr` | JIS tables. Big, so separate from other CJK. |
| `tables/cjk_gb.cr` | GB tables. |
| `tables/cjk_big5.cr` | Big5/CNS tables. |
| `tables/cjk_ksc.cr` | KSC tables. |
| `tables/ebcdic.cr` | All EBCDIC tables. Data. One file. |
| `codecs/utf8.cr` | Variable-length decoding, validation logic |
| `codecs/utf16.cr` | BOM detection, surrogate pairs, byte order |
| `codecs/utf32.cr` | BOM detection, byte order |
| `codecs/utf7.cr` | Stateful base64 codec — unique state machine |
| `codecs/gb18030.cr` | Algorithmic 4-byte ranges — unique logic |
| `codecs/iso2022_jp.cr` | Escape-sequence state machine |
| `codecs/iso2022_cn.cr` | Escape-sequence state machine |
| `codecs/iso2022_kr.cr` | Escape-sequence state machine |
| `codecs/hz.cr` | ~{...~} framing state machine |
| `transliteration.cr` | Fallback mapping tables for //TRANSLIT |

**~20 files.** Each one exists for a reason. If two encodings use the same logic
with different data, they don't get separate files — they share a function and
have separate table entries.

### Performance Expectations

On modern hardware (M1/M2/Intel 12th gen+, DDR4+):

| Scenario | Expected | Bottleneck |
|----------|----------|------------|
| ASCII text, any ASCII-superset pair | 4-8 GB/s | Memory bandwidth |
| UTF-8 → UTF-8 (passthrough) | 4-8 GB/s | Memory bandwidth |
| ISO-8859-1 → UTF-8 | 1-2 GB/s | UTF-8 emit (1-2 bytes per input byte) |
| Windows-1252 → UTF-8 | 500MB-1GB/s | Table lookup + UTF-8 emit |
| EUC-JP → UTF-8 (Japanese text) | 200-400 MB/s | 2D table lookup per CJK char |
| GB18030 → UTF-8 | 100-200 MB/s | Algorithmic decode for 4-byte seqs |
| System iconv on same data | Baseline | We should match or beat this |

These are achievable because:
1. ASCII runs (which dominate most text) run at memory bandwidth
2. Table lookups are O(1) with no branches
3. No indirect calls in the hot path
4. No heap allocations in the hot path
5. No unnecessary abstraction layers between the data and the work
