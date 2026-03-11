# stdlib Replacement Plan — Replace libiconv with charconv

## Status: Implemented

All steps below are complete. See the implementation section at the bottom.

## Goal

When a Crystal project does `require "charconv/stdlib"`, all encoding operations
(`String#encode`, `String.new(bytes, encoding)`, `IO#set_encoding`) use charconv
instead of the C libiconv library. No other code changes required in the consuming project.

## How Crystal uses libiconv today

All encoding goes through one struct: `Crystal::Iconv` (`crystal/iconv.cr`).

Three consumers:
1. `String.encode` (`string.cr:1814-1840`) — one-shot conversion with 1024-byte output buffer
2. `IO::Encoder` (`io/encoding.cr:29-59`) — streaming UTF-8 → target encoding
3. `IO::Decoder` (`io/encoding.cr:61-256`) — streaming target encoding → UTF-8

All three call the same interface:
```crystal
iconv = Crystal::Iconv.new(from, to, invalid)
err = iconv.convert(pointerof(inbuf_ptr), pointerof(inbytesleft),
                    pointerof(outbuf_ptr), pointerof(outbytesleft))
if err == Crystal::Iconv::ERROR
  iconv.handle_invalid(...)
end
iconv.close
```

The `convert` method uses the POSIX iconv pointer-advancing convention:
- Advances `*inbuf` and decrements `*inbytesleft` by bytes consumed
- Advances `*outbuf` and decrements `*outbytesleft` by bytes written
- Returns `(size_t)(-1)` on error, sets `Errno.value` to `EILSEQ`/`EINVAL`/`E2BIG`
- Returns 0 on success

Special call: `convert(NULL, NULL, &outbuf, &outbytesleft)` flushes stateful
encoders and resets state.

The struct has two instance variables: `@skip_invalid : Bool` and `@iconv : LibIconv::IconvT`
(which is `Void*`).

## Strategy

Two compilation modes:

### Default (no flags): Monkey-patch Crystal::Iconv

Reopen the struct, add a `@charconv : CharConv::Converter?` field, override all four
methods (`initialize`, `convert`, `handle_invalid`, `close`). The original `@iconv` field
still exists but gets set to a null pointer — no code path reads it directly, all access
goes through the methods we override.

libiconv is still linked (Crystal's `lib_iconv.cr` has `@[Link("iconv")]`) but never
called at runtime.

### With `-Dwithout_iconv`: Define Crystal::Iconv from scratch

When Crystal is compiled with `without_iconv`:
- `crystal/iconv.cr` is NOT required → `Crystal::Iconv` doesn't exist
- `encoding_stubs.cr` provides stub `IO::Encoder`/`IO::Decoder` that raise `NotImplementedError`
- `String#encode` references `Crystal::Iconv` unconditionally but is dead code unless called

We define the complete `Crystal::Iconv` struct and provide real `IO::Encoder`/`IO::Decoder`
implementations. No libiconv dependency at all — verified with `otool -L`.

## Implementation Details

### ConvertStatus enum (`types.cr`)

```crystal
enum ConvertStatus
  OK     # All input consumed
  E2BIG  # Output buffer full
  EILSEQ # Invalid byte sequence in input
  EINVAL # Incomplete multibyte sequence at end of input
end
```

### convert_with_status (`converter.cr`)

The conversion loops return `{consumed, written, status}`. The status is determined
by examining WHY conversion stopped:
- All input consumed → `OK`
- Output buffer full (ASCII copy or encode TOOSMALL) → `E2BIG`
- Decode returns status -1 (ILSEQ) and IGNORE not set → `EILSEQ`
- Decode returns status 0 (TOOFEW) → `EINVAL`

The original `convert(src, dst)` delegates to `convert_with_status` and drops the status.
Single copy of each conversion loop — no duplication.

### Bridge module (`stdlib.cr`)

`CharConv::StdlibBridge` provides shared logic used by both paths:
- `create_converter(from, to, invalid)` — strips `//IGNORE` from `from` encoding,
  creates `CharConv::Converter`
- `convert(...)` — bridges pointer-advancing API to slice-based API, sets errno
- `handle_invalid(...)` — skips byte or raises based on skip_invalid flag

### `//IGNORE` on `from` encoding

Crystal appends `//IGNORE` to BOTH `from` and `to` when `invalid == :skip` (on non-BSD).
CharConv handles `//IGNORE` via the `to` encoding's flags and applies it to both decode
and encode errors. We strip `//IGNORE` from `from` before creating the converter.

### Flush / reset

The iconv NULL-inbuf convention maps to:
- `converter.flush_encoder(dst, 0)` — emit pending stateful bytes
- `converter.reset` — reset codec state

## File changes

| File | Change |
|------|--------|
| `src/charconv/types.cr` | Added `ConvertStatus` enum |
| `src/charconv/converter.cr` | Unified loops to return status; `convert` delegates to `convert_with_status`; `flush_encoder` now public |
| `src/charconv/stdlib.cr` | Crystal::Iconv replacement — both default and `without_iconv` paths |
| `spec/stdlib_patch_spec.cr` | 29 tests: String#encode, IO encoding, roundtrips, stateful encodings, edge cases |

## Risks

1. **Crystal version coupling** — If Crystal changes `Crystal::Iconv` internals, the
   monkey-patch breaks. Pin to Crystal >= 1.19.1. Test against new Crystal releases.

2. **Null @iconv** — Set to null pointer in default path. No stdlib code reads it
   directly — verified by reading `crystal/iconv.cr`.

3. **BSD __iconv** — FreeBSD/DragonFly use `LibC.__iconv` with `ICONV_F_HIDE_INVALID`.
   Our override replaces the entire `convert` method, so this is handled.

4. **Thread safety** — Same as libiconv: converter handles are not thread-safe. Crystal
   creates per-IO Encoder/Decoder instances, so no new risk.

## Usage for consumers

```yaml
# shard.yml
dependencies:
  charconv:
    github: <repo>/charconv
```

```crystal
# To use charconv API directly:
require "charconv"
result = CharConv.convert(input, "Shift_JIS", "UTF-8")

# To replace libiconv for all stdlib encoding:
require "charconv/stdlib"
# Now String#encode, IO encoding, etc. all use charconv
"café".encode("ISO-8859-1")  # uses charconv, not libiconv

# To fully remove libiconv dependency:
# compile with: crystal build app.cr -Dwithout_iconv
```
