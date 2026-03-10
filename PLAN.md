# iconvcr — Remaining Work Plan

A pure Crystal clone of GNU libiconv. All 6 original implementation phases are complete.
150+ encodings implemented across all families (ASCII, Unicode, CJK, EBCDIC, Mac, etc.).

This plan covers the remaining work to reach a v0.1.0 release.

## Current State

- **548 tests, 29 failures, 28 errors** (as of 2026-03-10)
- All failures are in exhaustive/comparison tests against system iconv
- Core converter, all codecs, tables, transliteration, and flags are implemented
- No CI/CD, no real README, no IO streaming wrapper

## Bug #1: NUL Byte (0x00) Dropped for Non-ASCII-Superset Encodings

**Affected:** All 28 non-ASCII-superset encodings (Mac*, CP864, VISCII, EBCDIC*, TCVN)
**Cause:** `converter.cr:437-439` — the `convert_general` loop skips any decoded
character where `codepoint == 0 && status > 0`. This was intended to handle stateful
escape sequences (which return codepoint 0 to mean "consumed bytes, no character
produced"), but it incorrectly drops legitimate NUL bytes (U+0000).

```crystal
# Current (broken):
if dr.codepoint == 0 && dr.status > 0
  src_pos += dr.status
  next
end

# Fix: only skip for stateful codecs
```

**Fix:** Guard the skip with a check for stateful encodings only. Stateful codecs
(ISO-2022-*, UTF-7, HZ) use codepoint 0 + status > 0 as a signal for escape sequence
consumption. Table-driven and other codecs never produce this signal — a decoded
codepoint of 0 is always a real NUL.

**Impact:** Fixes 28 of the 29 decode failures (1 byte each) and 28 of the 28 encode
errors (which cascade from decode failures in round-trip tests).

## Bug #2: TCVN Encoding Has 45 Byte Mismatches

**Affected:** TCVN (TCVN-5712, Vietnamese)
**Symptoms:** 45 bytes decode differently than macOS system iconv, including ASCII-range
bytes (0x41 'A', 0x42 'B', etc.). Also fails the comparison_spec ASCII test.

**Likely Causes (investigate in order):**
1. **Name mismatch:** macOS system iconv may use a different name or variant for TCVN
   than what our mapping tables encode. The TCVN standard has multiple revisions.
2. **Table source mismatch:** The .TXT mapping file used to generate our table may
   differ from the version macOS iconv uses internally.
3. **Control character remapping:** TCVN remaps some bytes in the 0x00-0x1F and
   0x80-0xFF ranges. Our table may have these mappings wrong or incomplete.

**Fix:** Dump both our decode table and system iconv's byte-by-byte output for all 256
bytes, diff them, and update the table to match system iconv. If the encoding name
doesn't match, add the correct alias.

## Feature #1: IO Streaming Wrapper

The planned public API in the original design includes:

```crystal
def convert(input : IO, output : IO, buffer_size : Int32 = 8192)
```

This is not yet implemented. The core streaming `convert(Bytes, Bytes)` works, so
the IO wrapper is straightforward: read chunks from input IO, convert, write to
output IO, loop until EOF.

**Implementation:**
- Add to `Converter` class in `converter.cr`
- Read `buffer_size` bytes from input into a stack buffer
- Call `convert(src, dst)` in a loop
- Handle partial consumption (shift remaining bytes forward)
- Flush stateful encoders at EOF

## Feature #2: README Documentation

Replace the boilerplate README with real content:
- Project description and motivation
- Installation instructions (shard.yml)
- API usage examples (one-shot, streaming, IO)
- Supported encodings list (or link to list_encodings)
- Performance characteristics
- Flags (//IGNORE, //TRANSLIT)
- License

## Feature #3: GitHub Actions CI

Add `.github/workflows/ci.yml`:
- Run `crystal spec` on push/PR
- Test on latest Crystal + minimum supported version (1.19.1)
- Matrix: macOS + Linux (encoding tables may differ between system iconvs)
- Benchmark job (non-blocking, for tracking regressions)

## Feature #4: Performance Validation

Run benchmarks against performance targets from the original plan:

| Operation | Target |
|-----------|--------|
| UTF-8 → UTF-8 (ASCII text) | >4 GB/s |
| ASCII through any ASCII-superset pair | >4 GB/s |
| ISO-8859-1 → UTF-8 | >1 GB/s |
| Single-byte → UTF-8 | >500 MB/s |
| EUC-JP → UTF-8 | >200 MB/s |
| GB18030 → UTF-8 | >100 MB/s |

Identify and fix any that miss their targets. The bench_spec.cr exists but hasn't
been run systematically against these targets.

## Execution Order

### Phase A: Fix Test Failures (est. 1 day)
1. Fix NUL byte bug in `convert_general` (guard with stateful check)
2. Run tests — expect 28 fewer failures
3. Investigate and fix TCVN mismatches (table diff + update)
4. Run full test suite — target: 0 failures

### Phase B: IO Streaming + Polish (est. 1 day)
1. Implement `convert(IO, IO)` wrapper
2. Add tests for IO streaming (large files, multi-chunk, stateful encodings)
3. Run performance benchmarks, document results
4. Write README

### Phase C: CI/CD + Release Prep (est. 0.5 day)
1. Add GitHub Actions workflow
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
