# charconv

A pure Crystal implementation of GNU libiconv. Converts text between 150+ character
encodings using Unicode (UCS-4) as a pivot, with performance-first design.

## Features

- **150+ encodings**: ASCII, UTF-8, UTF-16/32, ISO-8859-*, Windows codepages, Mac encodings,
  CJK (Shift_JIS, EUC-JP, GBK, Big5, EUC-KR, GB18030, ...), EBCDIC, and more
- **Fast**: 8-byte ASCII scanner with memcpy for ASCII-superset pairs, enum-based dispatch
  compiling to jump tables, table-driven single-byte codecs, zero allocations in the hot path
- **Correct**: Exhaustive byte-level tests against system iconv for every encoding
- **Streaming**: Buffer-based API for zero-copy conversion, plus IO wrapper for convenience
- **GNU iconv compatible**: Supports `//IGNORE`, `//TRANSLIT`, and combined flags

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  charconv:
    github: jackthorne/charconv
```

## Usage

### One-shot conversion

```crystal
require "charconv"

# String/Bytes → Bytes
result = CharConv.convert("Hello, World!", "UTF-8", "ISO-8859-1")
result = CharConv.convert(input_bytes, "Shift_JIS", "UTF-8")

# With flags
result = CharConv.convert(input, "UTF-8", "ASCII//TRANSLIT")   # transliterate
result = CharConv.convert(input, "UTF-8", "ASCII//IGNORE")     # skip failures
```

### Streaming (buffer-based)

```crystal
converter = CharConv::Converter.new("EUC-JP", "UTF-8")

# You provide the buffers — zero allocations
src_consumed, dst_written = converter.convert(input_bytes, output_bytes)
# Call repeatedly until input is exhausted
```

### IO streaming

```crystal
File.open("input.txt", "r") do |input|
  File.open("output.txt", "w") do |output|
    CharConv.convert(input, output, "Shift_JIS", "UTF-8")
  end
end

# Or with a Converter instance for more control
converter = CharConv::Converter.new("GB18030", "UTF-8")
converter.convert(input_io, output_io, buffer_size: 16384)
```

### Thread Safety

`Converter` instances are **not** thread-safe — they hold mutable codec state for
stateful encodings (ISO-2022-JP, UTF-7, HZ, etc.). Do not share a converter across
fibers or threads. Instead, call `#dup` to create an independent copy:

```crystal
converter = CharConv::Converter.new("ISO-2022-JP", "UTF-8")

# Each fiber gets its own copy with fresh state
10.times do
  spawn do
    my_conv = converter.dup
    my_conv.convert(input_bytes, output_bytes)
  end
end
```

### Error handling

charconv offers two error handling styles: status codes for streaming, and exceptions
for one-shot conversion.

**Status codes (streaming)**

`convert_with_status` returns a `ConvertStatus` enum indicating why conversion stopped:

| Status | Meaning | Action |
|--------|---------|--------|
| `OK` | All input consumed | Done — read `dst[0, written]` |
| `E2BIG` | Output buffer full | Flush written bytes, call again with remaining input |
| `EILSEQ` | Invalid byte sequence | Error at `src[consumed]` — handle or abort |
| `EINVAL` | Incomplete sequence | Need more input bytes, or error at EOF |

```crystal
converter = CharConv::Converter.new("UTF-8", "ISO-8859-1")
src = input_bytes
dst = Bytes.new(src.size * 2)

consumed, written, status = converter.convert_with_status(src, dst)
case status
when .ok?     then io.write(dst[0, written])
when .e2_big? then # grow buffer or flush and retry with src[consumed..]
when .eilseq? then raise "Invalid byte at position #{consumed}"
when .einval? then raise "Incomplete sequence at end of input"
end
```

**Exceptions (one-shot)**

The one-shot `CharConv.convert` raises `CharConv::ConversionError` on failure:

```crystal
begin
  result = CharConv.convert(input, "UTF-8", "ISO-8859-1")
rescue ex : CharConv::ConversionError
  puts ex.message # e.g. "Conversion failed at byte 42 (42/100 bytes consumed)"
end
```

**Using flags instead of error handling**

`//IGNORE` silently skips invalid bytes and unencodable characters.
`//TRANSLIT` attempts ASCII approximations (e.g. `é` → `e`, `©` → `(c)`).
Combine both for maximum tolerance:

```crystal
# Skip what can't be transliterated
result = CharConv.convert(input, "UTF-8", "ASCII//TRANSLIT//IGNORE")
```

### Buffer sizing for streaming

When using `convert` or `convert_with_status` with your own buffers:

- **Safe default**: `src.size * 4` covers worst-case expansion (1-byte source → 4-byte UTF-8)
- **Exact ceiling**: `src.size * converter.to.max_bytes_per_char` — never overestimates
- **Same-family conversions** (e.g. ISO-8859-1 → ISO-8859-2): output ≤ input, so `src.size` suffices
- **If `E2BIG` is returned**: double the buffer and retry, or flush written bytes and continue

```crystal
converter = CharConv::Converter.new("EUC-JP", "UTF-8")
src = File.read("input.dat").to_slice
dst = Bytes.new(src.size * converter.to.max_bytes_per_char)
consumed, written, status = converter.convert_with_status(src, dst)
```

### Stateful encodings

ISO-2022-JP, ISO-2022-CN, ISO-2022-KR, UTF-7, and HZ use escape sequences to
switch between character sets. This means:

1. **Call `flush_encoder` after the last chunk** to emit any pending escape sequences
   (e.g. the switch-back-to-ASCII sequence in ISO-2022-JP):

   ```crystal
   converter = CharConv::Converter.new("UTF-8", "ISO-2022-JP")
   consumed, written = converter.convert(src, dst)
   flush_len = converter.flush_encoder(dst, written)
   output.write(dst[0, written + flush_len])
   ```

2. **Call `reset` before reusing** the converter for a new document — otherwise
   the encoder assumes it's continuing the previous stream's state.

3. **One-shot and IO methods handle this automatically** — `flush_encoder` and
   `reset` are only needed when using the buffer-based streaming API directly.

### Querying encodings

```crystal
CharConv.encoding_supported?("UTF-8")       # => true
CharConv.encoding_supported?("NONEXISTENT") # => false
CharConv.list_encodings                      # => ["ASCII", "UTF-8", ...]
```

## Supported Encodings

**Unicode**: ASCII, UTF-8, UTF-16BE/LE/BOM, UTF-32BE/LE/BOM, UCS-2, UCS-4, UTF-7, C99, Java

**Western European**: ISO-8859-1/15, CP1252, MacRoman, HP-ROMAN8, NEXTSTEP

**Central/Eastern European**: ISO-8859-2/3/4/10/13/14/16, CP1250, MacCentralEurope

**Cyrillic**: ISO-8859-5, CP1251, KOI8-R, KOI8-U, KOI8-RU, MacCyrillic, MacUkraine

**Greek**: ISO-8859-7, CP1253, MacGreek

**Turkish**: ISO-8859-9, CP1254, MacTurkish

**Hebrew**: ISO-8859-8, CP1255, MacHebrew

**Arabic**: ISO-8859-6, CP1256, MacArabic, CP864

**Thai**: ISO-8859-11, TIS-620, CP874, MacThai

**Vietnamese**: VISCII, TCVN, CP1258

**Japanese**: EUC-JP, Shift_JIS, CP932, ISO-2022-JP, ISO-2022-JP-1, ISO-2022-JP-2

**Chinese (Simplified)**: GB2312, GBK, GB18030, EUC-CN, HZ, ISO-2022-CN

**Chinese (Traditional)**: Big5, CP950, Big5-HKSCS, EUC-TW

**Korean**: EUC-KR, CP949, ISO-2022-KR, JOHAB

**DOS/IBM**: CP437, CP737, CP775, CP850, CP852, CP855, CP857, CP858, CP860-CP866, CP869

**EBCDIC**: CP037, CP273, CP277, CP278, CP280, CP284, CP285, CP297, CP423, CP424, CP500, CP905, CP1026

**Other**: ARMSCII-8, Georgian-Academy, Georgian-PS, PT154, KOI8-T, KZ-1048, MULELAO-1, ATARIST, RISCOS-LATIN1

## Replacing libiconv in Crystal's stdlib

charconv can transparently replace Crystal's libiconv dependency for all stdlib
encoding operations (`String#encode`, `String.new(bytes, encoding)`, `IO#set_encoding`).

```crystal
require "charconv/stdlib"

# All stdlib encoding now uses charconv — no libiconv calls at runtime
"café".encode("ISO-8859-1")
String.new(bytes, "Shift_JIS")

io = File.open("data.txt")
io.set_encoding("EUC-JP")
io.gets_to_end  # decoded through charconv
```

By default, libiconv is still linked but never called. To fully remove the libiconv
dependency, compile with `-Dwithout_iconv`:

```sh
crystal build app.cr -Dwithout_iconv
```

## Performance

charconv vs system libiconv, 1 MB input, `--release` mode.

<!-- BENCH:START - Generated by: crystal spec spec/bench_spec.cr --release -->

| Conversion | charconv | system iconv | Speedup |
|---|---|---|---|
| ASCII → ASCII | 73.39 µs | 11.89 ms | **162.0×** |
| UTF-8 → ISO-8859-1 (mixed Latin) | 3.43 ms | 14.62 ms | **4.3×** |
| ISO-8859-1 → UTF-8 | 2.08 ms | 14.24 ms | **6.9×** |
| UTF-8 → UTF-8 (mixed widths) | 4.92 ms | 11.98 ms | **2.4×** |
| CP1252 → UTF-8 | 2.50 ms | 17.24 ms | **6.9×** |
| UTF-8 → CP1252 (mixed Latin) | 3.50 ms | 14.50 ms | **4.1×** |
| UTF-16BE → UTF-8 (mixed widths) | 3.73 ms | 10.83 ms | **2.9×** |
| UTF-8 → UTF-16LE | 4.57 ms | 10.11 ms | **2.2×** |

<!-- BENCH:END -->

*Measured on Apple M3 Pro, Crystal 1.19.1, macOS. Run `crystal spec spec/bench_spec.cr --release` to reproduce.*

## Architecture

Every conversion goes through a Unicode pivot:

```
Source bytes → UCS-4 codepoint → Target bytes
  decode()        (pivot)         encode()
```

For ASCII-superset encoding pairs (the vast majority), an 8-byte word scanner
identifies ASCII runs and memcpys them directly, only falling back to the
decode-pivot-encode loop for non-ASCII characters. This means ASCII-heavy text
converts at memory bandwidth.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design rationale.

## Minimal Build

By default, charconv embeds lookup tables for all 150+ encodings including CJK
(~2 MB of table data). To build a smaller binary with only Western encodings:

```sh
crystal build app.cr -Dcharconv_minimal --release
```

The minimal set includes: ASCII, UTF-8, ISO-8859-1 through -16, CP1250-1258,
KOI8-R/U, Mac encodings, DOS codepages, EBCDIC, UTF-16/32, UTF-7, C99, Java,
and all other single-byte encodings. CJK encodings (Shift_JIS, EUC-JP, GBK,
Big5, GB18030, EUC-KR, ISO-2022-*, HZ, etc.) are excluded — attempting to use
them will return `EILSEQ`/`ILUNI` errors (the stubs reject all input).

## Development

```sh
crystal spec                        # run all tests
crystal spec spec/bench_spec.cr --release  # run benchmarks
```

## License

[MIT](LICENSE)
