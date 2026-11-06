// An example for the cbor package.
//
// It encodes a small structure, decodes it back, and prints the values.
//
// Run with: goose run examples/roundtrip.goose
import std;
import cbor from "..";

fn main() {
    var bytes: u8[>..] = [];
    cbor::encode_map_head(bytes, 2);
    cbor::encode_text(bytes, "name");
    cbor::encode_text(bytes, "goose");
    cbor::encode_text(bytes, "count");
    cbor::encode_uint(bytes, 3);

    var values: cbor::Value[>..] = [];
    var scratch: u8[>..] = [];
    let t, ok = cbor::decode(bytes[..], values, scratch);
    assert(ok);
    let root = t.values[t.root];
    let name, f1 = cbor::map_get(t, root, "name");
    assert(f1);
    let text, f2 = cbor::as_text(name);
    assert(f2);
    print("name: ", text);

    let count, f3 = cbor::map_get(t, root, "count");
    assert(f3);
    let num, f4 = cbor::as_uint(count);
    assert(f4);
    print("count: ", num);
    print("bytes: ", bytes.len);
    return 0;
}
