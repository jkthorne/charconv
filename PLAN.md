# charconv — Project Plan

Pure Crystal implementation of GNU libiconv. 150+ character encodings,
Unicode (UCS-4) pivot, performance-first design.

**Status: Feature-complete, unreleased. Ship v0.1.0.**

---

## What's Built

The library is production-ready. 150+ encodings across every major family
(ASCII, Unicode, 64 single-byte, 21 CJK, EBCDIC, exotics). Three API surfaces
(one-shot, streaming buffer, IO), stdlib bridge, `//IGNORE` and `//TRANSLIT`
flags. 636 tests, 0 failures on macOS + Ubuntu. Binary-embedded tables (228
`.bin` files, 2 MB). Differential fuzzing against system iconv on weekly CI.
Zero external dependencies.

Performance: 2–162x faster than system libiconv across every benchmark.

| Conversion | charconv | system iconv | Speedup |
|---|---|---|---|
| ASCII → ASCII | 69 µs | 11.0 ms | **159x** |
| ISO-8859-1 → UTF-8 | 430 µs | 13.7 ms | **32x** |
| CP1252 → UTF-8 | 647 µs | 16.0 ms | **25x** |
| UTF-8 → ISO-8859-1 | 2.19 ms | 13.7 ms | **6.2x** |
| UTF-8 → CP1252 | 2.14 ms | 13.9 ms | **6.5x** |
| UTF-16BE → UTF-8 | 3.51 ms | 9.84 ms | **2.8x** |
| UTF-8 → UTF-8 | 4.45 ms | 11.0 ms | **2.5x** |
| UTF-8 → UTF-16LE | 4.28 ms | 9.24 ms | **2.2x** |

*1 MB input, `--release`, Apple M3 Pro.*

---

## Ship v0.1.0

Nothing has been released. No git tags exist. All hardening work (thread-safety
docs, allocation cap, UTF-8 fast path, minimal build flag, extended fuzzing) is
already on master. The first release gets everything.

- [ ] Tag `v0.1.0`, push tag
- [ ] Verify shard installable via `github: jkthorne/charconv`
- [ ] Fix README minimal-build description (says "produce incorrect results"
  but stubs correctly return ILSEQ/ILUNI errors)

**Ship first. Everything else comes after.**

---

## v0.2.0: Upstream + Polish

The highest-impact work is getting charconv into Crystal's stdlib. Everything
else in this section makes the library easier to adopt.

### Crystal Stdlib Integration

The stdlib bridge (`charconv/stdlib`) monkey-patches `Crystal::Iconv`. The
endgame is replacing Crystal's libiconv dependency entirely — every Crystal
program that touches encoding would benefit.

- [ ] Open a Crystal RFC/discussion to gauge core team interest
- [ ] If receptive: extract a clean patch against `Crystal::Iconv`, submit PR
- [ ] If not: improve `require "charconv/stdlib"` docs and make the monkey-patch
  story more prominent

This is the single highest-leverage thing charconv can do. A stdlib merge means
150+ encodings and 2–162x speedups for every Crystal user, with zero opt-in
effort.

### API Documentation

The public API works but isn't well-documented for newcomers.

- [ ] Run `crystal doc` and verify output quality
- [ ] Document `ConvertStatus` enum (OK, E2BIG, EILSEQ, EINVAL) in README
- [ ] Add error handling examples (what happens with invalid input, how to use
  `//IGNORE` vs checking status codes)
- [ ] Add buffer sizing guidance for streaming API
- [ ] Document stateful encoding implications (ISO-2022-JP, UTF-7, HZ need
  `reset` between independent chunks)

### CJK Encode Fast Paths

The single-byte fast paths skip the UCS-4 pivot for all 64 single-byte codecs.
CJK codecs still go through the full pivot. For CJK-heavy workloads (log
processing, text pipelines), dedicated fast paths for EUC-JP ↔ UTF-8,
GBK ↔ UTF-8, and EUC-KR ↔ UTF-8 would close the gap.

- [ ] Benchmark CJK paths to establish baseline (currently unmeasured)
- [ ] Inline UTF-8 decode in CJK encode paths (same pattern as single-byte)
- [ ] Consider 2D table → direct UTF-8 emit (skip UCS-4 intermediate)

The single-byte fast paths proved the pattern: inline decode, skip the pivot,
go straight from source bytes to target bytes. CJK is the same idea with
2D table lookups instead of 1D.

---

## Future Ideas

Independent items, any order, no commitment. Each one should be motivated by
a real user need before starting.

### SIMD ASCII Scanner

The 8-byte scalar scanner runs at ~13 GB/s on M3 (memory-bandwidth limited for
large buffers). NEON 16B reads could double throughput for cache-resident data.

Not worth doing yet:
- Crystal has no SIMD intrinsics — needs inline ASM or C interop
- We're already 162x faster than system iconv for ASCII
- The scalar scanner is simple and correct
- **Do this only if someone profiles a real workload where ASCII scanning is the bottleneck**

### Encoding Detection

Companion feature to conversion. BOM detection is already implemented internally.
Statistical detection (byte frequency analysis), HTML meta charset parsing, and
XML encoding declaration parsing are common needs.

**This should be a separate shard** (`chardet` or similar), not part of charconv.
Conversion and detection are different problems with different APIs.

### StaticArray for ENCODING_INFO

`Registry::ENCODING_INFO` is a heap `Array` built at startup. Could be a
compile-time `StaticArray` indexed by `EncodingID.value`. Zero throughput
impact — queried once per `Converter.new`. Pure cleanup.

---

## Rejected Ideas

Things considered and explicitly rejected. Adding this context prevents
revisiting decisions that have already been thought through.

1. **Abstract codec interface / plugin system** — Enum dispatch compiles to a
   jump table. Virtual dispatch adds indirection in the hot path for no benefit.
   The encoding set is fixed; there's no user-defined encoding use case worth
   the overhead.

2. **Lazy table loading** — The 64 encode tables (64 KB each) are built at
   startup. Lazy init saves startup memory but adds a branch to every encode
   call. Not worth it: tables are only built for encodings referenced in code,
   and Crystal's linker eliminates unreachable ones.

3. **Async/fiber-aware streaming** — Crystal's IO is already cooperative
   (`IO.read` yields). Explicit fiber awareness adds complexity with no benefit.

4. **Windows support** — Crystal doesn't support Windows. When it does, charconv
   works out of the box (pure Crystal, embedded tables, no system dependencies).

5. **Crystal source tables** — Binary embedding (228 `.bin` files) is smaller,
   compiles faster, and is easier to regenerate. Don't go back to Crystal
   constant arrays.

---

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md).

Key decisions: UCS-4 pivot, 8-byte ASCII word scan, enum dispatch → jump table,
`StaticArray` decode/encode tables, stack-allocated result structs (no heap in
hot path), binary-embedded lookup tables via `read_file` at compile time.
