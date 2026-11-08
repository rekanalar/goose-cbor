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

// encode_canonical writes the node v in the order of RFC 7049: the
// map keys sort by their encoded length first, then by their bytes.
fn encode_canonical(t: Tree&, v: Value&, out: u8[>..]&) -> bool {
    var tmp: u8[>..] = [];
    return encode_tree(t, v, out, tmp, true);
}

// is_canonical tells whether the bytes are in the core deterministic form
// of RFC 8949: the minimal heads, the shortest float and the map keys
// sorted by their bytes. It decodes the input, encodes it again and
// compares the bytes. Broken input gives false.
fn is_canonical(s: const u8[:]) -> bool {
    var values: Value[>..] = [];
    var scratch: u8[>..] = [];
    let t, ok = decode(s, values, scratch);
    if !ok { return false; }
    var out: u8[>..] = [];
    var tmp: u8[>..] = [];
    if !encode_tree(t, t.values[t.root], out, tmp, false) { return false; }
    return out[..] == s;
}
