// An example for the cbor package: deterministic output.
//
// It writes a map with the keys out of order, sorts it as RFC 8949
// section 4.2.1 asks, and writes floats and a date tag in the shortest form.
//
// Run with: goose run examples/deterministic.goose
import std;
import cbor from "..";

fn main() {
    var out: u8[>..] = [];
    var tmp: u8[>..] = [];
    cbor::encode_map_head(out, 3);
    let start = out.len;
    cbor::encode_text(out, "when");
    cbor::encode_epoch(out, 1363896240);
    cbor::encode_text(out, "b");
    cbor::encode_float(out, 1.5);
    cbor::encode_text(out, "a");
    cbor::encode_float(out, 100000.0);
    assert(cbor::sort_map(out, start, 3, tmp));
    for b in out { print(b, " "); }
    print("");
    print("bytes: ", out.len);
    return 0;
}
