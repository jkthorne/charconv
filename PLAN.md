# iconvcr — Remaining Work Plan

A pure Crystal clone of GNU libiconv. All 6 original implementation phases are complete.
150+ encodings implemented across all families (ASCII, Unicode, CJK, EBCDIC, Mac, etc.).

This plan covers the remaining work to reach a v0.1.0 release.

## Current State

- **548 tests, 0 failures, 0 errors** (as of 2026-03-10)
- All encoding families passing exhaustive correctness tests against system iconv
- Core converter, all codecs, tables, transliteration, and flags are implemented
- No CI/CD, no real README, no IO streaming wrapper

## Completed: Phase A — Bug Fixes

### Bug #1: NUL Byte Dropped for Non-ASCII-Superset Encodings (FIXED)

**Root cause:** `converter.cr` `convert_general` loop had `if dr.codepoint == 0 && dr.status > 0`
which skipped ALL decoded NUL codepoints, not just stateful escape sequence signals.

**Fix:** Added `&& @from.stateful` guard — one line change. This was the sole cause of
all 57 test failures (29 failures + 28 errors). The TCVN table was correct; its 44 letter
positions genuinely map to U+0000 in macOS's TCVN encoding, and the NUL-skip bug was
dropping them.

## Remaining Work

### Phase B: IO Streaming + Polish (est. 1 day)

#### Feature #1: IO Streaming Wrapper

The planned public API includes but has not implemented:

```crystal
def convert(input : IO, output : IO, buffer_size : Int32 = 8192)
```

The core streaming `convert(Bytes, Bytes)` works, so the IO wrapper is straightforward:
read chunks from input IO, convert, write to output IO, loop until EOF.

**Implementation:**
- Add to `Converter` class in `converter.cr`
- Read `buffer_size` bytes from input into a buffer
- Call `convert(src, dst)` in a loop
- Handle partial consumption (shift remaining bytes forward)
- Flush stateful encoders at EOF

#### Feature #2: README Documentation

Replace the boilerplate README with real content:
- Project description and motivation
- Installation instructions (shard.yml)
- API usage examples (one-shot, streaming, IO)
- Supported encodings list (or link to list_encodings)
- Performance characteristics
- Flags (//IGNORE, //TRANSLIT)
- License

#### Feature #3: Performance Validation

Run benchmarks against performance targets:

| Operation | Target |
|-----------|--------|
| UTF-8 → UTF-8 (ASCII text) | >4 GB/s |
| ASCII through any ASCII-superset pair | >4 GB/s |
| ISO-8859-1 → UTF-8 | >1 GB/s |
| Single-byte → UTF-8 | >500 MB/s |
| EUC-JP → UTF-8 | >200 MB/s |
| GB18030 → UTF-8 | >100 MB/s |

### Phase C: CI/CD + Release Prep (est. 0.5 day)

1. Add `.github/workflows/ci.yml` (crystal spec on push/PR, macOS + Linux matrix)
2. Tag v0.1.0 release
3. Publish to shards registry

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
