# charconv — Project Status

A pure Crystal clone of GNU libiconv. Converts text between 150+ character
encodings using Unicode (UCS-4) as a pivot, with performance-first design.

**Status: Feature-complete. Ready for v0.1.0 release.**

## Summary

- **558 tests, 0 failures, 0 errors**
- 150+ encodings across all families (ASCII, Unicode, CJK, EBCDIC, Mac, etc.)
- 2.2x–136x faster than system iconv across all benchmarks
- Streaming API (buffer-based and IO), one-shot convenience API
- `//IGNORE`, `//TRANSLIT`, and combined flag support
- GitHub Actions CI (macOS + Ubuntu, Crystal latest + 1.19.1)

## Benchmarks

| Operation              | charconv     | System iconv | Speedup |
|------------------------|-------------|-------------|---------|
| ASCII → ASCII          | 12.25 GB/s  | 90 MB/s     | 136x    |
| ISO-8859-1 → UTF-8    | 580 MB/s    | 72 MB/s     | 8.0x    |
| CP1252 → UTF-8         | 487 MB/s    | 60 MB/s     | 8.1x    |
| UTF-16BE → UTF-8       | 291 MB/s    | 99 MB/s     | 2.9x    |
| UTF-8 → ISO-8859-1    | 266 MB/s    | 72 MB/s     | 3.7x    |
| UTF-8 → UTF-16LE       | 227 MB/s    | 105 MB/s    | 2.2x    |
| UTF-8 → UTF-8          | 213 MB/s    | 90 MB/s     | 2.4x    |

## Implementation History

### Phase 1: Core Converter + Benchmarks
- DecodeResult/EncodeResult structs, EncodingID enum, Converter class
- Conversion loop with 8-byte ASCII fast scanner
- ASCII, UTF-8, ISO-8859-1 codecs
- Registry, public API, comparison benchmarks vs system iconv

### Phase 2: Single-Byte Encodings (~64 encodings)
- Table generator (`tools/generate_tables.cr`) reading Unicode .TXT files
- ISO-8859-2–16, CP1250–1258, KOI8-R/U/RU, Mac encodings, DOS codepages
- Exhaustive byte-level correctness tests against system iconv

### Phase 3: Unicode Family (~19 encodings)
- UTF-16BE/LE/BOM, UTF-32BE/LE/BOM with surrogate pair handling
- UCS-2/UCS-4 variants with native/swapped byte order
- UTF-7 (stateful base64), C99/Java escape notation

### Phase 4: CJK Encodings (~21 encodings)
- Japanese: EUC-JP, Shift_JIS, CP932, ISO-2022-JP/-1/-2
- Chinese: GB2312, GBK, GB18030 (algorithmic 4-byte), EUC-CN, Big5, CP950, Big5-HKSCS, EUC-TW, HZ, ISO-2022-CN
- Korean: EUC-KR, CP949, ISO-2022-KR, JOHAB
- CJK table generators, exhaustive + fuzz tests

### Phase 5: EBCDIC + Remaining (~30 encodings)
- EBCDIC: CP037, CP273, CP277, CP278, CP280, CP284, CP285, CP297, CP423, CP424, CP500, CP905, CP1026
- Additional: CP856, CP922, CP853, CP1046, CP1124–1163, ATARIST, KZ-1048, MULELAO-1, RISCOS-LATIN1, TCVN

### Phase 6: Transliteration + Flags
- 645-entry transliteration table with generator
- `//IGNORE`, `//TRANSLIT`, combined flag parsing
- Fuzz test suite for //IGNORE across all encoding families

### Phase A: Bug Fixes
- Fixed NUL byte (U+0000) dropped for non-ASCII-superset encodings
- Root cause: `convert_general` skipped all codepoint-0 results, not just stateful escape signals
- One-line fix: added `&& @from.stateful` guard

### Phase B: IO Streaming + Polish
- `Converter#convert(IO, IO)` and `CharConv.convert(IO, IO, from, to)`
- README with full API docs, encoding list, architecture overview
- Performance validation: all targets met or exceeded

### Phase C: CI/CD
- GitHub Actions: test matrix (macOS + Ubuntu, Crystal latest + 1.19.1)
- Benchmark job on main pushes

## Release Checklist

1. Push to GitHub, verify CI passes
2. `git tag v0.1.0 && git push --tags`
3. Register on shards registry

## Architecture Reference

See [ARCHITECTURE.md](ARCHITECTURE.md) for the performance-first design rationale.

**Key decisions:**
- Pivot through UCS-4: Source bytes → UCS-4 codepoint → Target bytes
- ASCII fast path: 8-byte word scan + memcpy for ASCII runs
- Enum dispatch: `case` on `EncodingID` compiles to jump tables, not Proc pointers
- Table-driven: `StaticArray(UInt16, 256)` decode + `StaticArray(UInt8, 65536)` encode
- Stack-allocated results: DecodeResult (8B) and EncodeResult (4B), no heap
- Zero allocations in streaming hot path
