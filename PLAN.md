# charconv — Project Plan

Pure Crystal implementation of GNU libiconv. 150+ character encodings,
Unicode (UCS-4) pivot, performance-first design.

**Status: Phase 2 complete. Ship v0.2.0.**

---

## Where We Are

The library is feature-complete and hardened. 150+ encodings, exhaustive
correctness tests against system iconv, 2–162x faster across every benchmark,
complete stdlib bridge, zero dependencies.

What's done:
- 636+ tests, 0 failures across macOS + Ubuntu
- All encoding families: ASCII, Unicode (UTF-7/8/16/32, UCS-2/4, C99, Java),
  64 single-byte (ISO, Windows, KOI8, Mac, DOS, EBCDIC), 21 CJK (EUC-JP,
  Shift_JIS, GBK, GB18030, Big5, EUC-KR, ISO-2022-*, HZ), plus exotics
- Streaming (buffer, IO), one-shot, and stdlib monkey-patch APIs
- `//IGNORE`, `//TRANSLIT` (645 entries), combined flags
- CI: GitHub Actions, macOS + Ubuntu, Crystal latest + 1.19.1
- Binary-embedded tables (228 .bin files, 2 MB) replacing Crystal source arrays
- Specialized fast paths: ISO-8859-1 ↔ UTF-8 (bit math), all 64 single-byte → UTF-8
  (packed table), UTF-8 → all 64 single-byte (inline decode + table),
  UTF-8 → UTF-8 (validate + copy, no pivot)
- Thread-safety documented, `Converter#dup` for per-fiber cloning
- One-shot allocation capped at 64 MB with grow-and-retry loop
- `-Dcharconv_minimal` compile flag (2.9 MB → 1.7 MB, excludes CJK tables)
- Extended differential fuzzing with CJK generators, weekly CI workflow

### Current Benchmarks

1 MB input, `--release`, Apple M3 Pro:

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

---

## Phase 1: Ship v0.1.0

Tag and publish. The `perf/fast-path` work is already merged to master.

- [x] Merge `perf/fast-path` to master (7 commits: binary tables + fast paths)
- [x] Run full spec suite locally — 596 examples, 0 failures (2026-03-12)
- [x] Run benchmarks `--release` — all paths faster or equal, ISO-8859-1→UTF-8 jumped from 6.9x to 32x (2026-03-12)
- [ ] Tag `v0.1.0`, push tag (`git tag v0.1.0 && git push origin v0.1.0`)
- [ ] Verify shard installable via `github: jkthorne/charconv`

**Rule: don't add features before shipping. The library is complete and tested.
Delaying for polish is how projects die on the vine.**

---

## Phase 2: Harden (v0.2.0)

These are the things that matter for production use by other people.
Ordered by impact, not effort.

### 2.1 Thread Safety ✓

- [x] Add thread-safety note to README usage section
- [x] Add thread-safety note to `Converter` class doc comment
- [x] Implement `Converter#dup` for per-fiber cloning (shares immutable tables, fresh `CodecState`)

### 2.2 Binary Size Budget ✓

Crystal's `read_file` embeds all table data unconditionally. Full binary: 2.9 MB.

- [x] Measured binary size: 2.9 MB full, 1.7 MB minimal (41% reduction)
- [x] Added `-Dcharconv_minimal` compile flag excluding CJK tables/codecs
- [x] Stub codec modules return ILSEQ/ILUNI for excluded encodings
- [x] Documented in README

### 2.3 Cap One-Shot Allocation ✓

- [x] Replaced worst-case upfront allocation with grow-and-retry loop
- [x] Starts at `input.size * 2` (floor 64 bytes), doubles on E2BIG
- [x] Calls `reset` before each retry (critical for stateful codecs)
- [x] Hard cap at 64 MB with `ConversionError` on overflow

### 2.4 Differential Fuzzing ✓

- [x] Extended fuzz spec with CJK roundtrip correctness + crash-safety tests
- [x] Added targeted generators: GB18030 4-byte, ISO-2022-JP escapes,
  UTF-7 base64, Big5-HKSCS high-range pairs
- [x] Iteration count configurable via `FUZZ_DEEP` / `FUZZ_MAX_SIZE` env vars
- [x] Weekly scheduled CI workflow (Monday 3 AM UTC, 5000 iterations, `--release`)

### 2.5 UTF-8 → UTF-8 Fast Path ✓

- [x] Implemented `convert_utf8_to_utf8` — validates inline, copies directly
- [x] Reuses `scan_ascii_run` + memcpy for ASCII runs
- [x] Validates overlong, surrogates, range limits matching `Decode.utf8`
- [x] Benchmarks pending `--release` measurement (expected significant improvement)

---

## Phase 3: Expand (v0.3.0+)

Lower priority. Each item is independent and can be shipped in any order.

### 3.1 SIMD ASCII Scanner

The 8-byte scalar scanner is memory-bandwidth limited on large buffers (~13 GB/s
on M3). For cache-resident data (< L2), NEON 16B or 128-bit reads could double
throughput. Worth doing only if someone profiles a workload where this matters.

- Crystal doesn't expose SIMD intrinsics natively — would need inline ASM or
  C interop via `lib` bindings
- The win is modest: system iconv at 90 MB/s means we're already 162x ahead
- **Defer until someone asks for it**

### 3.2 Crystal Stdlib PR

The stdlib bridge (`charconv/stdlib`) monkey-patches `Crystal::Iconv`. The
clean endgame is upstreaming this as Crystal's default iconv implementation,
eliminating the libiconv system dependency entirely.

- [ ] Evaluate Crystal core team appetite (open RFC/discussion)
- [ ] If receptive: extract minimal patch, submit PR
- [ ] If not: document `-Dwithout_iconv` usage more prominently

### 3.3 Encoding Detection

Common companion feature to conversion. Not in scope for the conversion library
itself, but could be a separate shard (`chardet`) that pairs with charconv.

- BOM detection (already implemented internally)
- Statistical detection (frequency analysis of byte distributions)
- HTML meta charset / XML encoding declaration parsing
- **Separate shard, not charconv's job**

### 3.4 StaticArray for ENCODING_INFO

`Registry::ENCODING_INFO` is a heap `Array` built at startup. Could be a
compile-time `StaticArray` indexed by `EncodingID.value`. Zero throughput
impact (queried once per `Converter.new`). Cleanliness only.

### 3.5 CJK Encode Fast Paths

The single-byte fast paths (generalized in `perf/fast-path`) skip the UCS-4
pivot for all 64 single-byte codecs. CJK codecs still go through the full
pivot. For high-throughput CJK workloads (log processing in Japanese data
centers, Chinese text pipelines), dedicated fast paths for EUC-JP ↔ UTF-8,
GBK ↔ UTF-8, and EUC-KR ↔ UTF-8 would help.

- [ ] Benchmark CJK paths to establish baseline
- [ ] Inline UTF-8 decode in CJK encode paths (same pattern as single-byte)
- [ ] Consider 2D table → direct UTF-8 emit (skip UCS-4 intermediate)

---

## What Not to Do

Things I've considered and rejected:

1. **Abstract codec interface / plugin system** — The enum dispatch compiles to
   a jump table. Virtual dispatch would add indirection in the hot path for no
   benefit. The encoding set is fixed; there's no user-defined encoding use case
   that justifies the overhead.

2. **Lazy table loading** — The 64 encode tables (64 KB each = 4 MB total) are
   built at startup. Lazy init would save startup memory but add a branch to
   every encode call. Not worth it: the tables are only built for encodings
   actually referenced in code, and Crystal's linker can eliminate unreachable
   ones.

3. **Async/fiber-aware streaming** — The IO streaming API already works with
   Crystal's fibers (IO.read yields). Adding explicit fiber awareness would
   add complexity with no benefit since Crystal's IO is already cooperative.

4. **Windows support** — Crystal doesn't support Windows. When it does, charconv
   will work out of the box (pure Crystal, no system dependencies beyond the
   tables which are embedded). No special effort needed.

5. **Rewrite tables as Crystal constants** — We just went the other direction
   (binary embedding). The binary files are smaller, faster to compile, and
   easier to regenerate. Don't go back.

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
- Binary-embedded lookup tables via `read_file` at compile time

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
10. **Fast paths** — ISO-8859-1 ↔ UTF-8 bit math, generalized single-byte ↔ UTF-8
11. **Binary tables** — Replaced Crystal source arrays with 228 binary .bin files
12. **Hardening** — Thread-safety docs + `#dup`, allocation cap, UTF-8 fast path, minimal build flag, extended fuzzing
