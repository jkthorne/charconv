# iconvcr — Remaining Work Plan

A pure Crystal clone of GNU libiconv. All 6 original implementation phases are complete.
150+ encodings implemented across all families (ASCII, Unicode, CJK, EBCDIC, Mac, etc.).

This plan covers the remaining work to reach a v0.1.0 release.

## Current State

- **558 tests, 0 failures, 0 errors** (as of 2026-03-10)
- All encoding families passing exhaustive correctness tests against system iconv
- Core converter, all codecs, tables, transliteration, flags, and IO streaming implemented
- README written, benchmarks validated
- No CI/CD

## Completed: Phase A — Bug Fixes

### Bug #1: NUL Byte Dropped for Non-ASCII-Superset Encodings (FIXED)

**Root cause:** `converter.cr` `convert_general` loop had `if dr.codepoint == 0 && dr.status > 0`
which skipped ALL decoded NUL codepoints, not just stateful escape sequence signals.

**Fix:** Added `&& @from.stateful` guard — one line change. This was the sole cause of
all 57 test failures (29 failures + 28 errors). The TCVN table was correct; its 44 letter
positions genuinely map to U+0000 in macOS's TCVN encoding, and the NUL-skip bug was
dropping them.

## Completed: Phase B — IO Streaming + Polish

### Feature #1: IO Streaming Wrapper (DONE)

Added `Converter#convert(IO, IO)` and `Iconvcr.convert(IO, IO, from, to)`.
Handles multi-chunk processing, partial consumption at buffer boundaries,
stateful encoder flush at EOF, and //IGNORE flag. 10 tests.

### Feature #2: README Documentation (DONE)

Full README with API examples (one-shot, streaming, IO), supported encodings
list, architecture overview, and development instructions.

### Feature #3: Performance Validation (DONE)

All benchmarks beat system iconv by 2.2x–136x:

| Operation              | iconvcr     | System iconv | Speedup |
|------------------------|-------------|-------------|---------|
| ASCII → ASCII          | 12.25 GB/s  | 90 MB/s     | 136x    |
| ISO-8859-1 → UTF-8    | 580 MB/s    | 72 MB/s     | 8.0x    |
| CP1252 → UTF-8         | 487 MB/s    | 60 MB/s     | 8.1x    |
| UTF-16BE → UTF-8       | 291 MB/s    | 99 MB/s     | 2.9x    |
| UTF-8 → ISO-8859-1    | 266 MB/s    | 72 MB/s     | 3.7x    |
| UTF-8 → UTF-16LE       | 227 MB/s    | 105 MB/s    | 2.2x    |
| UTF-8 → UTF-8          | 213 MB/s    | 90 MB/s     | 2.4x    |

## Completed: Phase C — CI/CD + Release Prep

### CI/CD (DONE)

Added `.github/workflows/ci.yml`:
- Test matrix: macOS + Ubuntu, Crystal latest + 1.19.1
- Runs `crystal spec` on push to main and PRs
- Benchmark job on main pushes (release mode, non-blocking)

### Release

To publish v0.1.0:
1. Push to GitHub, verify CI passes
2. `git tag v0.1.0 && git push --tags`
3. Register on shards registry

## Architecture Reference

See [ARCHITECTURE.md](ARCHITECTURE.md) for the performance-first design rationale,
data structure diagrams, and dispatch strategy.

## Original Design Decisions (preserved)

- **Pivot through UCS-4:** Source bytes → UCS-4 codepoint → Target bytes
- **ASCII fast path:** 8-byte word scan + memcpy for ASCII runs
- **Enum dispatch:** `case` on `EncodingID` compiles to jump tables, not Proc pointers
- **Table-driven:** Single-byte = `StaticArray(UInt16, 256)` decode + `StaticArray(UInt8, 65536)` encode
- **CJK:** 2D array decode + two-level page table encode
- **Stack-allocated results:** `DecodeResult` (8 bytes) and `EncodeResult` (4 bytes), no heap
- **Zero allocations in hot path:** User provides buffers for streaming API
