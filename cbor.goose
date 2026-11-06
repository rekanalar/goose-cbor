// cbor - CBOR encoding and decoding for Goose. RFC 8949.
//
// The package encodes the major types into the canonical minimal form
// and decodes them into a tree of typed values or one typed value at a
// time. Broken bytes fault instead of giving partial values.
//
// The repository is goose-cbor. The import name is "cbor".
namespace cbor;

import std;
import encode;
import value;
import decode;
