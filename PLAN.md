# charconv — Project Plan

Pure Crystal implementation of GNU libiconv. 150+ character encodings,
Unicode (UCS-4) pivot, performance-first design.

**Status: Feature-complete. Cleanup before v0.1.0.**

## Current State

- 558 tests, 0 failures
- 150+ encodings (ASCII, Unicode, CJK, EBCDIC, Mac, DOS, etc.)
- 2.2x–136x faster than system iconv
- Streaming (buffer + IO), one-shot, and stdlib monkey-patch APIs
- `//IGNORE`, `//TRANSLIT`, combined flag support
- CI: macOS + Ubuntu, Crystal latest + 1.19.1

### Benchmarks

| Operation              | charconv     | System iconv | Speedup |
|------------------------|-------------|-------------|---------|
| ASCII → ASCII          | 12.25 GB/s  | 90 MB/s     | 136x    |
| ISO-8859-1 → UTF-8    | 580 MB/s    | 72 MB/s     | 8.0x    |
| CP1252 → UTF-8         | 487 MB/s    | 60 MB/s     | 8.1x    |
| UTF-16BE → UTF-8       | 291 MB/s    | 99 MB/s     | 2.9x    |
| UTF-8 → ISO-8859-1    | 266 MB/s    | 72 MB/s     | 3.7x    |
| UTF-8 → UTF-16LE       | 227 MB/s    | 105 MB/s    | 2.2x    |
| UTF-8 → UTF-8          | 213 MB/s    | 90 MB/s     | 2.4x    |

---

## What's Left: Pre-Release Cleanup

### 1. Unify the four conversion loops → two

**Problem:** `converter.cr` has four nearly-identical loops:
- `convert_ascii_fast` (36 lines)
- `convert_ascii_fast_status` (52 lines)
- `convert_general` (41 lines)
- `convert_general_status` (53 lines)

The `_status` variants exist for the stdlib iconv bridge. They return
`{Int32, Int32, ConvertStatus}` instead of `{Int32, Int32}`. The non-status
variants use `handle_encode` (which returns a heap-checked `{Int32, Int32}?`)
while the status variants inline the encode/translit/ignore logic directly.

This is ~182 lines of conversion loop where ~100 are duplicated.

**Fix:** Make the status-returning versions the single implementation.
`convert(src, dst)` calls `convert_with_status` and discards the status.
Delete `convert_ascii_fast`, `convert_general`, and `handle_encode`. This:
- Cuts ~80 lines from the hottest file in the project
- Eliminates the `{Int32, Int32}?` return from the per-character path
- Makes one place to fix bugs in the conversion loop, not two

The `_status` variants already inline the encode logic and are strictly
more capable. No performance regression — the non-status versions were
doing more work (tuple allocation + nil check) per character anyway.

**Files:** `converter.cr`
**Risk:** Low — exhaustive and comparison tests catch any regression.

### 2. Kill string allocations in stdlib.cr constructor

**Problem:** `Crystal::Iconv#initialize` does:
```crystal
clean_from = from.gsub("//IGNORE", "")       # allocates String
original_from = clean_from.gsub(...)          # allocates again
original_to = to.gsub(...)                    # allocates again
```

Three `gsub` allocations on every converter creation. Not hot-path, but
sloppy — the stdlib path creates converters for every `String#encode`,
`String.new(bytes, encoding)`, and `IO#set_encoding` call.

**Fix:** Use `String#index("//")` and `String#byte_slice` to strip suffixes.
Zero allocations for the common case (no `//` suffix present).

**Files:** `stdlib.cr`
**Risk:** None — stdlib_patch_spec covers this.

### 3. Commit the stdlib patch

**Problem:** `stdlib.cr` and `stdlib_patch_spec.cr` are untracked. The
converter changes (adding `convert_with_status` and `ConvertStatus`) are
staged but uncommitted.

**Fix:** Commit the stdlib iconv bridge as a clean commit after the
loop unification is done.

**Files:** `stdlib.cr`, `stdlib_patch_spec.cr`, `converter.cr`, `types.cr`

### 4. Document the unaligned load assumption

**Problem:** `scan_ascii_run` casts `Pointer(UInt8)` to `Pointer(UInt64)`:
```crystal
word = (src.to_unsafe + pos).as(Pointer(UInt64)).value
```

`Bytes` doesn't guarantee 8-byte alignment. On ARM64 and x86-64 this
works (hardware handles unaligned loads with at most a small penalty),
but the assumption should be explicit.

**Fix:** Add a one-line comment noting the unaligned access is intentional
and safe on the target architectures (x86-64, ARM64).

**Files:** `converter.cr`
**Risk:** None.

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
