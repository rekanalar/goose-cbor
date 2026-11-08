// An example for the cbor package: reading a stream of items.
//
// It reads two items from one buffer. The first call gives the number of
// bytes that the item used, and the second call reads the rest. It also
// looks the keys of a map up by their kind.
//
// Run with: goose run examples/stream.goose

import std;
import cbor from "..";

fn main() {
    // Two items: the map {"a": 1, 5: 2} and the text "end".
    var bytes: u8[>..] = [];
    cbor::encode_map_head(bytes, 2);
    cbor::encode_text(bytes, "a");
    cbor::encode_uint(bytes, 1);
    cbor::encode_uint(bytes, 5);
    cbor::encode_uint(bytes, 2);
    cbor::encode_text(bytes, "end");

    var values: cbor::Value[>..] = [];
    var scratch: u8[>..] = [];
    let tree, used, ok = cbor::decode_first(bytes[..], values, scratch);
    if !ok {
        print("the first item faults");
        return 1;
    }
    print("the first item took ", used, " bytes");

    // The map answers a lookup by the kind of the key.
    let root = tree.values[tree.root];
    let value, found = cbor::map_get_uint(tree, root, 5);
    if found {
        let n, nok = cbor::as_uint(value);
        print("the key 5 holds ", n);
    }

    // The rest of the buffer holds the next item.
    var values2: cbor::Value[>..] = [];
    var scratch2: u8[>..] = [];
    let tree2, used2, ok2 = cbor::decode_first(bytes[used..], values2, scratch2);
    if !ok2 {
        print("the second item faults");
        return 1;
    }
    let text, tok = cbor::as_text(tree2.values[tree2.root]);
    print("the second item took ", used2, " bytes and holds ", text);
    return 0;
}
