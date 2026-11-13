// The tests of the canonical forms: the RFC 7049 order, the canonical check and the cbor2 oracle.
namespace canonical_tests;

import std;
import cbor from "..";
import hex_helpers;
import cbor2_cases;

fn test_rfc7049_sort() {
    // The map holds the byte-string key "abc" and the text key "z".
    var out: u8[>..] = [];
    cbor::encode_map_head(out, 2);
    let start = out.len;
    cbor::encode_bytes(out, "abc");
    cbor::encode_uint(out, 2);
    cbor::encode_text(out, "z");
    cbor::encode_uint(out, 1);
    var tmp: u8[>..] = [];
    assert(cbor::sort_map(out, start, 2, tmp));
    // The bytewise order of RFC 8949 puts the byte-string key first.
    var text: u8[>..] = [];
    hex_helpers::hex(text, "a24361626302617a01");
    assert(out == text);
    // The order of RFC 7049 puts the shorter text key first.
    out = [];
    cbor::encode_map_head(out, 2);
    let start2 = out.len;
    cbor::encode_bytes(out, "abc");
    cbor::encode_uint(out, 2);
    cbor::encode_text(out, "z");
    cbor::encode_uint(out, 1);
    tmp = [];
    assert(cbor::sort_map_rfc7049(out, start2, 2, tmp));
    var text2: u8[>..] = [];
    hex_helpers::hex(text2, "a2617a014361626302");
    assert(out == text2);
}


fn test_canonical_check() {
    assert(cbor::is_canonical("\xf9\x3e\x00"));
    assert(!cbor::is_canonical("\xfb\x3f\xf8\x00\x00\x00\x00\x00\x00"));
    assert(cbor::is_canonical("\x01"));
    assert(!cbor::is_canonical("\x18\x01"));
    assert(!cbor::is_canonical("\x1a\x00\x00\x00\x01"));
}

// The oracle cases of Python cbor2. Each case decodes, encodes again in
// the order of RFC 7049, and compares the bytes with the ones of cbor2.
fn test_cbor2_cases() {
    for c, i in cbor2_cases::CASE_INPUT {
        var bytes: u8[>..] = [];
        hex_helpers::hex(bytes, c);
        var values: cbor::Value[>..] = [];
        var scratch: u8[>..] = [];
        let tree, ok = cbor::decode(bytes[..], values, scratch);
        if !ok {
            print("FAIL cbor2 case ", i, ": the decode faults");
            assert(false);
        }
        var out: u8[>..] = [];
        if !cbor::encode_canonical(tree, tree.values[tree.root], out) {
            print("FAIL cbor2 case ", i, ": the encode faults");
            assert(false);
        }
        var want: u8[>..] = [];
        hex_helpers::hex(want, cbor2_cases::CASE_WANT[i]);
        if out != want {
            print("FAIL cbor2 case ", i, ": got ", out.len, " bytes, want ", want.len);
            assert(false);
        }
    }
}
