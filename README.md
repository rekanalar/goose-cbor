# goose-cbor

[![ci](https://github.com/rekanalar/goose-cbor/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-cbor/actions/workflows/ci.yml)

CBOR encoding and decoding for the [Goose](https://github.com/aardappel/goose) programming language. The
rules are RFC 8949.

The package encodes the basic types in the preferred serialization of
RFC 8949 section 4.1. Floats take 16, 32 or 64 bits, whichever keeps the
value. A map has the core deterministic order (section 4.2.1) after
`sort_map`. Named writers and readers cover the date, bignum and decimal
tags.

The decoder gives a tree of typed values, or one value at a time.
Broken bytes fault instead of giving partial values. Pure Goose, no C.

## Install

Add this to the root file of the program that uses it:

```goose
import cbor from "rekanalar/goose-cbor@v0.2.0";
```

## API

| Function | What it does |
|---|---|
| `encode_uint`, `encode_int` | write one integer in the minimal form |
| `encode_bytes`, `encode_text` | write one string with its length header |
| `encode_array_head`, `encode_map_head` | write one container header |
| `encode_tag`, `encode_bool`, `encode_null` | write one value |
| `encode_float` | write a float in the shortest form; NaN is `f97e00` |
| `encode_float64` | write a float in the full 8-byte form |
| `sort_map(out, start, n, tmp)` | sort the pairs of a map in the bytewise order of the keys |
| `encode_datetime_string`, `encode_epoch`, `encode_epoch_float` | write a tag 0 or tag 1 date |
| `encode_bignum`, `encode_decimal` | write a bignum (tag 2 or 3) or a decimal (tag 4) |
| `decode(s, values, scratch)` | reads one value into the arrays of the caller |
| `read_uint`, `read_int`, `read_text`, `read_bytes` | read one typed value from the front |
| `read_float`, `read_bool`, `read_null` | read one typed value from the front |

The tree access helpers are `as_uint`, `as_int`, `as_text`, `as_bytes`,
`as_float`, `as_bool`, `child_at`, `array_len` and `map_get`. The tag
helpers are `as_tag`, `as_datetime_string`, `as_epoch` and `as_bignum`.
The constants `TAG_EPOCH`, `TAG_BIGNUM_POS` and the like name the tags. The text
and byte payloads are spans over the input, so the input must outlive
the tree. The decode walk uses an explicit stack with a depth cap of
64; deeper input faults.

## Deterministic maps

Write the map head, note `start = out.len`, and write the pairs in any
order. Then call `sort_map(out, start, n, tmp)`. Sort a nested map
before the map that holds it. `sort_map` gives false when the bytes are
not n pairs.

## Limits

- The order is bytewise (RFC 8949). It is not the length-first order of
  RFC 7049, which Python `cbor2` uses with `canonical=True`.
- `sort_map` does not reject duplicate keys.
- The encoder writes every NaN as `f97e00`. A NaN payload is lost.
- `map_get` finds text keys only.
- There is no writer for tag 5 (bigfloat) and no date parse.
- A bignum has no conversion to a number type.
- The decoder accepts non-preferred forms and indefinite lengths. It
  does not check that the input is deterministic.

## Test

```bash
goose run test/run.goose
goose run examples/roundtrip.goose
goose run examples/deterministic.goose
```

## License

MIT
