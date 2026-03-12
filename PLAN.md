# charconv — Plan

**Status: Feature-complete, unreleased. Ship v0.1.0.**

150+ encodings, 2-162x faster than system libiconv, 636 tests passing,
zero dependencies. See README for benchmarks.

---

## v0.1.0: Ship It

- [ ] Tag `v0.1.0`, push tag
- [ ] Verify shard installable via `github: jkthorne/charconv`
- [x] ~~Fix README minimal-build description~~

---

## v0.2.0: Upstream + Polish

### Crystal Stdlib Integration (highest leverage)

Replace Crystal's libiconv dependency entirely via `charconv/stdlib` bridge.

- [ ] Open Crystal RFC/discussion for core team interest
- [ ] If receptive: submit PR against `Crystal::Iconv`
- [ ] If not: improve monkey-patch docs

### CJK Encode Fast Paths

Single-byte codecs already skip the UCS-4 pivot. Apply the same pattern to
EUC-JP, GBK, EUC-KR (inline UTF-8 decode, skip pivot, direct emit).

- [x] ~~Benchmark CJK paths to establish baseline~~
- [x] ~~Inline UTF-8 decode in CJK encode paths~~
- [x] ~~`convert_utf8_to_cjk()` fast path for EUC-JP, GBK, EUC-CN, EUC-KR~~

### API Documentation

- [x] ~~All items complete~~ (doc comments, README examples, crystal doc)

---

## Future Ideas

Do only if motivated by a real user need.

- **SIMD ASCII scanner** — NEON 16B reads could help cache-resident data, but
  Crystal lacks SIMD intrinsics and we're already 162x faster for ASCII.
- **Encoding detection** — Should be a separate shard (`chardet`), not charconv.
- **StaticArray for ENCODING_INFO** — Pure cleanup, zero throughput impact.

---

## Rejected

1. **Plugin/virtual dispatch** — Enum jump table is faster; encoding set is fixed.
2. **Lazy table loading** — Adds branch to every encode call; linker already eliminates unused tables.
3. **Async/fiber-aware streaming** — Crystal IO is already cooperative.
4. **Windows support** — Crystal doesn't support Windows yet; charconv is pure Crystal so it'll work when Crystal does.
5. **Crystal source tables** — Binary `.bin` embedding is smaller and compiles faster.

---

Architecture: see [ARCHITECTURE.md](ARCHITECTURE.md).
