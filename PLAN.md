# charconv — Project Plan

Pure Crystal implementation of GNU libiconv. 150+ character encodings,
Unicode (UCS-4) pivot, performance-first design.

**Status: Ready for v0.1.0 release.**

## Current State

- 558 tests, 0 failures
- 150+ encodings (ASCII, Unicode, CJK, EBCDIC, Mac, DOS, etc.)
- 2.2x-136x faster than system iconv
- Streaming (buffer + IO), one-shot, and stdlib monkey-patch APIs
- `//IGNORE`, `//TRANSLIT`, combined flag support
- CI: macOS + Ubuntu, Crystal latest + 1.19.1

### Benchmarks

| Operation              | charconv     | System iconv | Speedup |
|------------------------|-------------|-------------|---------|
| ASCII -> ASCII          | 12.25 GB/s  | 90 MB/s     | 136x    |
| ISO-8859-1 -> UTF-8    | 580 MB/s    | 72 MB/s     | 8.0x    |
| CP1252 -> UTF-8         | 487 MB/s    | 60 MB/s     | 8.1x    |
| UTF-16BE -> UTF-8       | 291 MB/s    | 99 MB/s     | 2.9x    |
| UTF-8 -> ISO-8859-1    | 266 MB/s    | 72 MB/s     | 3.7x    |
| UTF-8 -> UTF-16LE       | 227 MB/s    | 105 MB/s    | 2.2x    |
| UTF-8 -> UTF-8          | 213 MB/s    | 90 MB/s     | 2.4x    |

---

## Completed: Pre-Release Cleanup

All items done.

1. **Unify conversion loops** — Collapsed four loops (`convert_ascii_fast`,
   `convert_ascii_fast_status`, `convert_general`, `convert_general_status`)
   into two status-returning loops. `convert(src, dst)` delegates to
   `convert_with_status` and discards the status. Removed `handle_encode`.
2. **Kill string allocations in stdlib.cr** — Replaced `gsub` calls with
   `String#index("//")` + `String#byte_slice`. Zero allocations for the
   common case (no `//` suffix).
3. **Commit stdlib patch** — `stdlib.cr` and `stdlib_patch_spec.cr` tracked
   and committed.
4. **Document unaligned load** — Comment added to `scan_ascii_run` noting
   the intentional unaligned `UInt64` access on x86-64/ARM64.

---

## Future (Post v0.1.0)

These are not blocking release. They're noted for later.

### SIMD ASCII scanner

The 8-byte scalar scanner hits ~12 GB/s (memory bandwidth limited on
large buffers). For cache-resident data, NEON (16B) or AVX2 (32B) could
double throughput. The UTF-8 decode path could also benefit from SIMD
validation (see simdjson's approach). Not worth the complexity yet —
the current numbers already dominate system iconv.

### StaticArray for ENCODING_INFO

`Registry::ENCODING_INFO` is built at runtime as a heap-allocated `Array`.
Could be a compile-time `StaticArray` indexed by `EncodingID.value`.
The registry is queried once per converter creation so this doesn't affect
throughput, but it's cleaner. Low priority.

### Cap one-shot allocation

`convert(Bytes)` allocates `input.size * max_bytes_per_char * 4` for
translit mode. For UTF-7 (max=8) with translit, a 1MB input allocates
32MB. Could add a grow-and-retry strategy instead of worst-case upfront.
No one has hit this in practice.

---

## Architecture Reference

See [ARCHITECTURE.md](ARCHITECTURE.md).

**Key decisions:**
- Pivot through UCS-4: Source → UCS-4 codepoint → Target
- ASCII fast path: 8-byte word scan + memcpy for ASCII runs
- Enum dispatch: `case` on `EncodingID` compiles to jump table
- Table-driven: `StaticArray(UInt16, 256)` decode, `StaticArray(UInt8, 65536)` encode
- Stack-allocated results: DecodeResult (8B), EncodeResult (4B), no heap
- Zero allocations in streaming hot path

## Implementation History

1. **Core** — Converter, ASCII scanner, UTF-8/ASCII/ISO-8859-1, registry, benchmarks
2. **Single-byte** (~64) — Table generator, ISO-8859-*, CP125*, KOI8, Mac, DOS
3. **Unicode** (~19) — UTF-16/32 with BOM, UCS-2/4 variants, UTF-7, C99/Java
4. **CJK** (~21) — EUC-JP, Shift_JIS, CP932, GB*, Big5, EUC-KR, CP949, ISO-2022-*, HZ
5. **EBCDIC + remaining** (~30) — CP037-CP1026, CP856-CP1163, ATARIST, etc.
6. **Flags** — //IGNORE, //TRANSLIT, 645-entry transliteration table
7. **IO streaming** — `Converter#convert(IO, IO)`, module-level IO API
8. **Stdlib bridge** — `Crystal::Iconv` monkey-patch, `convert_with_status`
9. **CI** — GitHub Actions (macOS + Ubuntu, Crystal latest + 1.19.1)
