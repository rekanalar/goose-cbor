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
Broken bytes fault instead of giving partial values. The decoder never aborts on hostile input. Pure Goose, no C.

## Install

Add this to the root file of the program that uses it:

```goose
import cbor from "rekanalar/goose-cbor@v1.0.0";
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
| `encode_bigfloat` | write a bigfloat (tag 5) |
| `sort_map_rfc7049(out, start, n, tmp)` | sort the pairs of a map in the length-first order of RFC 7049 |
| `encode_canonical(t, v, out)` | write a decoded value in the length-first order |
| `decode(s, values, scratch)` | reads one value into the arrays of the caller |
| `decode_with(s, opts, values, scratch)` | reads one value under the options of `DecodeOpts` |
| `decode_first(s, values, scratch)` | reads the first item and gives the bytes it used |
| `is_canonical(s)` | tells whether the bytes hold the core deterministic form |
| `read_uint`, `read_int`, `read_text`, `read_bytes` | read one typed value from the front |
| `read_float`, `read_bool`, `read_null` | read one typed value from the front |

`DecodeOpts` holds the options of `decode_with`. `max_depth` is the
nesting limit, and the caller names 64 for the behaviour of `decode`.
`reject_dups` refuses a duplicate map key. `check_tags` checks the
shape of the tags 0 to 5 at decode.

The tree access helpers are `as_uint`, `as_int`, `as_text`, `as_bytes`,
`as_float`, `as_bool`, `child_at`, `array_len` and `map_get`.
The lookups `map_get_uint`, `map_get_int` and `map_get_bytes` find a key
of another kind than text.
`as_undefined` and `as_simple` read the simple values.
The tag helpers are `as_tag`, `as_datetime_string`, `as_epoch` and
`as_bignum`.
The tag helpers `bignum_as_int`, `as_bigfloat` and `datetime_to_epoch`
read the numbers and the date of a tag.

The constants `TAG_EPOCH`, `TAG_BIGNUM_POS` and the like name the tags.
The text and byte payloads are spans over the input, so the input must
outlive the tree. The decode walk uses an explicit stack with a depth
cap of 64; deeper input faults. `decode_with` names its own cap.

## Deterministic maps

Write the map head, note `start = out.len`, and write the pairs in any
order. Then call `sort_map(out, start, n, tmp)`. Sort a nested map
before the map that holds it. `sort_map` gives false when the bytes are
not n pairs.

## What the decoder checks

- A string length and a container count must fit in the bytes that are left. A bad one gives false and never aborts.
- The head bytes `1f`, `3f` and `df` give false. An indefinite map with a key and no value gives false.
- A text string holds valid UTF-8 only. The same holds for each chunk of an indefinite text string.
- `f7` is `undefined`. The simple values 0 to 19 and 32 to 255 decode as simple values.
- The two-byte forms of 0 to 31, and the bytes `fc` to `fe`, give false.

## Security

The package decodes bytes from people we do not know. These protections
go beyond the reference libraries.

- The decoder compares every declared length and count with the bytes that
  are left. A byte string with a length of many bytes faults instead of
  taking memory. Go `fxamacker/cbor` can take memory for a declared length.
- The nesting depth is capped at 64. Python `cbor2` has no cap, and Go
  stops at 32.
- The duplicate-key check refuses a map with more than 1024 pairs. The
  check compares every key with the later keys, so a map with many pairs
  would take much time.
- A text string must hold valid UTF-8, and so must each chunk of an
  indefinite text string. A program that puts a decoded text into a page
  or a command needs that.

These risks stay.

- The package writes nothing to a file, a command or a page.
- The decoder reads a tag as a number. The check of the tags 0 to 5 is
  optional, and it checks the shape of the tag only.
- A decoded byte string holds any bytes. The package does not change
  them.

## Limits

- `sort_map` gives the bytewise order of RFC 8949.
  `sort_map_rfc7049` gives the length-first order of RFC 7049,
  which Python `cbor2` uses with `canonical=True`.
- The encoder writes every NaN as `f97e00`. A NaN payload is lost.
  Python `cbor2` writes the same bytes and loses the payload too.
  Go `fxamacker/cbor` keeps the payload by default, with
  `NaNConvert.Off`. The two libraries disagree, and no RFC fixes one
  rule, so the package follows `cbor2`.
- The float code uses integer bit arithmetic only. It calls no `pow`, `log2` or `floor`.
  It never divides by zero, because the macOS arm64 JIT mis-evaluates those.
- The decoder accepts non-preferred forms and indefinite lengths.
  `is_canonical` tells whether the bytes hold the core deterministic
  form.
- `decode` reads one document. Bytes after it give false.
  `decode_first` reads the first item and gives the bytes it used,
  as Go `fxamacker/cbor` does with `UnmarshalFirst`.
- `decode` checks no tag content. `decode_with` with `check_tags` checks
  the shape of the tags 0 to 5 at decode, as `cbor2` does.
- The depth limit of `decode` is 64. `decode_with` names its own cap.
  `cbor2` has no limit and Go `fxamacker/cbor` stops at 32 by default.
- A duplicate map key is accepted by `decode`, as `cbor2` does.
  `decode_with` with `reject_dups` refuses it, as
  `fxamacker/cbor` does with `RejectDupMapKeyError`.
  The check compares every key with the later keys.
  A map with more than 1024 pairs gives false under that option.
- A decoded NaN keeps no payload and no sign. The bits of the NaN depend on the CPU.

## Test

The test program holds 850 generated cases from `cbor2`. They are 281 decode cases,
122 accept cases, 205 refuse cases and 242 encoder cases.
The script `test/make_cbor_cases.py` makes them with a fixed seed.

The test holds 120 more cases from `cbor2` with `canonical=True`.
The script `test/make_cbor2_cases.py` makes them.

The hand cases hold the 97 inputs of the audit against `cbor2` and
`fxamacker/cbor`. The hostile cases must finish in under one second.

```bash
goose run test/run.goose
goose run examples/roundtrip.goose
goose run examples/deterministic.goose
goose run examples/untrusted.goose
goose run examples/stream.goose
```

## License

MIT
