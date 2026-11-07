// An example for the cbor package: bytes from an untrusted peer.
//
// decode gives false for a bad document and never aborts. This example
// refuses a string that declares 2^64 minus 1 bytes, and reads a document
// that holds the simple value undefined.
//
// Run with: goose run examples/untrusted.goose
import std;
import cbor from "..";

fn main() {
    // A byte string with a declared length that no input can hold.
    var bad: u8[>..] = [0x5b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff];
    var values: cbor::Value[>..] = [];
    var scratch: u8[>..] = [];
    let t, ok = cbor::decode(bad[..], values, scratch);
    print("huge length accepted: ", ok);
    assert(!ok);

    // An array that holds undefined and the simple value 255.
    var doc: u8[>..] = [0x82, 0xf7, 0xf8, 0xff];
    var values2: cbor::Value[>..] = [];
    var scratch2: u8[>..] = [];
    let t2, ok2 = cbor::decode(doc[..], values2, scratch2);
    assert(ok2);
    let root = t2.values[t2.root];
    let first, f1 = cbor::child_at(t2, root, 0);
    assert(f1);
    print("first is undefined: ", cbor::as_undefined(first));
    let second, f2 = cbor::child_at(t2, root, 1);
    assert(f2);
    let n, isn = cbor::as_simple(second);
    print("second is simple: ", isn, " ", n);
    assert(cbor::as_undefined(first) && isn && n == 255);
    return 0;
}
