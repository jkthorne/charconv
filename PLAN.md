# charconv — Plan

## v0.1.0: Ship It

- [ ] Tag `v0.1.0`, push tag
- [ ] Verify shard installable via `github: jkthorne/charconv`

## v0.2.0: Crystal Stdlib Integration

Replace Crystal's libiconv dependency via `charconv/stdlib` bridge.

- [ ] Open Crystal RFC/discussion for core team interest
- [ ] If receptive: submit PR against `Crystal::Iconv`
- [ ] If not: improve monkey-patch docs

## Future Ideas

Do only if motivated by a real user need.

- **SIMD ASCII scanner** — Crystal lacks intrinsics; already 162x faster for ASCII.
- **Encoding detection** — Separate shard (`chardet`), not charconv.
