# charconv — Architecture (Performance-First)

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

## Architecture

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

# Conversion flags parsed from //TRANSLIT and //IGNORE suffixes
@[Flags]
enum ConversionFlags : UInt8
  Ignore  = 1  # Skip invalid input bytes and unencodable characters
  Translit = 2  # Try fallback transliteration before giving up
end

# Status returned from the conversion loop (maps to errno values)
enum ConvertStatus
  OK      # All input consumed
  E2BIG   # Output buffer full
  EILSEQ  # Invalid byte sequence in input
  EINVAL  # Incomplete multibyte sequence at end of input
end

# Encoding identity — an enum, not a string, not a Proc
# 189 values total: 64 single-byte, 23 Unicode variants, 13 CJK stateless,
# 8 CJK stateful, plus Mac encodings, EBCDIC, and special codecs (C99, JAVA)
enum EncodingID : UInt16
  ASCII
  UTF8
  ISO_8859_1
  ISO_8859_2
  # ... 64 single-byte ASCII-superset encodings
  # ... Mac encodings (non-ASCII-superset single-byte)
  # ... Unicode family (UTF-16 BE/LE, UTF-32 BE/LE, UCS-2/4 variants, UTF-7, C99, JAVA)
  # ... CJK stateless (EUC-JP, Shift_JIS, CP932, GBK, GB18030, Big5, EUC-KR, etc.)
  # ... CJK stateful (ISO-2022-JP/-JP1/-JP2, ISO-2022-CN/-CN-EXT, ISO-2022-KR, HZ)
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
def convert_with_status(src : Bytes, dst : Bytes) : {Int32, Int32, ConvertStatus}
  if @from.ascii_superset && @to.ascii_superset
    convert_ascii_fast(src, dst)
  else
    convert_general(src, dst)
  end
end

# ASCII scanner extracted as a separate inlined method
@[AlwaysInline]
private def scan_ascii_run(src : Bytes, pos : Int32) : Int32
  run_end = pos
  # 8 bytes at a time via unaligned UInt64 load (safe on x86-64 and ARM64)
  while run_end + 8 <= src.size
    word = (src.to_unsafe + run_end).as(Pointer(UInt64)).value
    break if word & 0x8080808080808080_u64 != 0
    run_end += 8
  end
  # Byte-at-a-time for trailing bytes
  while run_end < src.size && src.to_unsafe[run_end] < 0x80
    run_end += 1
  end
  run_end - pos  # returns length of ASCII run
end

private def convert_ascii_fast(src : Bytes, dst : Bytes) : {Int32, Int32, ConvertStatus}
  src_pos = 0
  dst_pos = 0

  while src_pos < src.size
    # Scan and copy ASCII run
    run_len = scan_ascii_run(src, src_pos)
    if run_len > 0
      avail = dst.size - dst_pos
      copy_len = run_len < avail ? run_len : avail
      (src.to_unsafe + src_pos).copy_to(dst.to_unsafe + dst_pos, copy_len)
      src_pos += copy_len
      dst_pos += copy_len
      next if copy_len < run_len  # output full → E2BIG
    end

    break if src_pos >= src.size

    # Decode/encode one non-ASCII character
    dr = decode_one(src, src_pos)
    # ... handles ILSEQ/TOOFEW with Ignore/Translit flags
    er = encode_one(dr.codepoint, dst, dst_pos)
    # ... handles ILUNI with Translit fallback
    src_pos += dr.status
    dst_pos += er.status
  end

  {src_pos, dst_pos, ConvertStatus::OK}
end

private def convert_general(src : Bytes, dst : Bytes) : {Int32, Int32, ConvertStatus}
  src_pos = 0
  dst_pos = 0
  # Handles BOM detection/emission for UTF-16/UTF-32 on first call
  while src_pos < src.size
    dr = decode_one(src, src_pos)
    # Stateful codecs may return codepoint 0 with status > 0 (escape sequences)
    er = encode_one(dr.codepoint, dst, dst_pos)
    src_pos += dr.status
    dst_pos += er.status
  end
  {src_pos, dst_pos, ConvertStatus::OK}
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

Total for 64 single-byte encodings:
  Decode: 64 × 512B = 32KB (trivial)
  Encode: 64 × 64KB = 4MB (loaded lazily, only 2 active at a time)
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
