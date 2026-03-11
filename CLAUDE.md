# CLAUDE.md

## Project Overview

Pure Crystal implementation of GNU libiconv. Converts text between 150+ character encodings using Unicode (UCS-4) as a pivot. Performance-first design with 8-byte ASCII scanner and zero-allocation hot paths.

## Commands

```bash
crystal spec                                     # Run all tests
crystal spec spec/charconv_spec.cr               # Core conversion tests
crystal spec spec/cjk_spec.cr                    # CJK encoding tests
crystal spec spec/unicode_spec.cr                # Unicode tests
crystal spec spec/bench_spec.cr --release        # Benchmarks
crystal spec spec/exhaustive_spec.cr             # Exhaustive byte-level tests vs system iconv
iconv -l                                         # List system iconv encodings (for comparison)
```

## Architecture

Every conversion goes through a Unicode pivot: `Source bytes → UCS-4 codepoint → Target bytes`. See `ARCHITECTURE.md` for full design rationale.

### Key Design Decisions

- **Enum-based dispatch** compiles to jump tables (no virtual dispatch)
- **8-byte ASCII scanner** processes ASCII runs at memory bandwidth via word-at-a-time comparison
- **Stack-allocated result structs** (`DecodeResult`, `EncodeResult`) — zero heap allocation in hot path
- **Table-driven single-byte codecs** — 512B decode table + 64KB encode table per encoding

### Source Layout

| File | Purpose |
|------|---------|
| `src/charconv/converter.cr` | Conversion loop, ASCII scanner, buffer management |
| `src/charconv/decode.cr` | Decode dispatch + non-trivial decode functions |
| `src/charconv/encode.cr` | Encode dispatch + non-trivial encode functions |
| `src/charconv/registry.cr` | Name normalization, 550+ alias resolution → EncodingID |
| `src/charconv/types.cr` | Result structs, EncodingID enum (189 values), CodecState, ConversionFlags, ConvertStatus |
| `src/charconv/stdlib.cr` | Crystal stdlib bridge — monkey-patches `Crystal::Iconv` for drop-in replacement |
| `src/charconv/tables/` | Single-byte (64 encodings), CJK, and GB18030 lookup tables |
| `src/charconv/codecs/` | Complex codecs (UTF-16, UTF-32, UTF-7, GB18030, ISO-2022-*, C99, etc.) |
| `src/charconv/transliteration.cr` | 645-entry //TRANSLIT fallback mappings |

### API

```crystal
# One-shot
CharConv.convert(input, "UTF-8", "ISO-8859-1")

# Streaming (zero-copy)
converter = CharConv::Converter.new("EUC-JP", "UTF-8")
src_consumed, dst_written = converter.convert(input_bytes, output_bytes)

# Streaming with iconv-compatible status
src_consumed, dst_written, status = converter.convert_with_status(input_bytes, output_bytes)
# status: ConvertStatus::OK | E2BIG | EILSEQ | EINVAL

# Flags
CharConv.convert(input, "UTF-8", "ASCII//TRANSLIT")   # transliterate
CharConv.convert(input, "UTF-8", "ASCII//IGNORE")     # skip failures
```

## Notes

- Requires Crystal >= 1.19.1
- No external dependencies
- See `PLAN.md` for roadmap
