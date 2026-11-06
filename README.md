# goose-cbor

[![ci](https://github.com/rekanalar/goose-cbor/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-cbor/actions/workflows/ci.yml)

CBOR encoding and decoding for the Goose programming language. The
rules are RFC 8949.

The package encodes integers, byte strings, text strings, arrays, maps,
booleans, null and floats into the canonical minimal form. It decodes
into a tree of typed values, or one typed value at a time with the read
API. Broken bytes fault instead of giving partial values. Pure Goose,
no C.

## Install

Add this to the root file of the program that uses it:

```goose
import cbor from "rekanalar/goose-cbor@v0.1.0";
```

## API

| Function | What it does |
|---|---|
| `encode_uint`, `encode_int` | write one integer in the minimal form |
| `encode_bytes`, `encode_text` | write one string with its length header |
| `encode_array_head`, `encode_map_head` | write one container header |
| `encode_tag`, `encode_bool`, `encode_null`, `encode_float` | write one value |
| `decode(s, values, scratch)` | reads one value into the arrays of the caller |
| `read_uint`, `read_int`, `read_text`, `read_bytes` | read one typed value from the front |
| `read_float`, `read_bool`, `read_null` | read one typed value from the front |

The tree access helpers are `as_uint`, `as_int`, `as_text`, `as_bytes`,
`as_float`, `as_bool`, `child_at`, `array_len` and `map_get`. The text
and byte payloads are spans over the input, so the input must outlive
the tree. The decode walk uses an explicit stack with a depth cap of
64; deeper input faults.

## License

MIT
