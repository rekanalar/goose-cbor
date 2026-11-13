// The tests of the decode options: first value, depth limit, duplicate keys and tag checks.
namespace decode_option_tests;

import std;
import cbor from "..";
import hex_helpers;

fn test_decode_first() {
    var bytes: u8[>..] = [];
    hex_helpers::hex(bytes, "0102");
    var values: cbor::Value[>..] = [];
    var scratch: u8[>..] = [];
    let tree, used, ok = cbor::decode_first(bytes[..], values, scratch);
    assert(ok);
    assert(used == 1);
    let n, nok = cbor::as_uint(tree.values[tree.root]);
    assert(nok);
    assert(n == 1);
    // The rest of the input stays readable.
    var values2: cbor::Value[>..] = [];
    var scratch2: u8[>..] = [];
    let tree2, used2, ok2 = cbor::decode_first(bytes[1..], values2, scratch2);
    assert(ok2);
    assert(used2 == 1);
    let n2, n2ok = cbor::as_uint(tree2.values[tree2.root]);
    assert(n2ok);
    assert(n2 == 2);
    // Broken input faults like decode.
    var values3: cbor::Value[>..] = [];
    var scratch3: u8[>..] = [];
    let _, _, ok3 = cbor::decode_first("\x1a\x00", values3, scratch3);
    assert(!ok3);
}

fn test_depth_option() {
    // 200 nested arrays.
    var bytes: u8[>..] = [];
    for i in 0..200 { bytes.push(0x81); }
    bytes.push(0x01);
    var opts = cbor::DecodeOpts { max_depth: 64, reject_dups: false, check_tags: false };
    var values: cbor::Value[>..] = [];
    var scratch: u8[>..] = [];
    let _, ok = cbor::decode_with(bytes[..], opts, values, scratch);
    assert(!ok);
    var opts2 = cbor::DecodeOpts { max_depth: 200, reject_dups: false, check_tags: false };
    var values2: cbor::Value[>..] = [];
    var scratch2: u8[>..] = [];
    let _, ok2 = cbor::decode_with(bytes[..], opts2, values2, scratch2);
    assert(ok2);
    // A limit below 1 faults.
    var opts3 = cbor::DecodeOpts { max_depth: 0, reject_dups: false, check_tags: false };
    var values3: cbor::Value[>..] = [];
    var scratch3: u8[>..] = [];
    let _, ok3 = cbor::decode_with("\x01", opts3, values3, scratch3);
    assert(!ok3);
}

fn test_duplicate_keys() {
    var bytes: u8[>..] = [];
    hex_helpers::hex(bytes, "a201020103");
    var opts = cbor::DecodeOpts { max_depth: 64, reject_dups: false, check_tags: false };
    var values: cbor::Value[>..] = [];
    var scratch: u8[>..] = [];
    let _, ok = cbor::decode_with(bytes[..], opts, values, scratch);
    assert(ok);
    var opts2 = cbor::DecodeOpts { max_depth: 64, reject_dups: true, check_tags: false };
    var values2: cbor::Value[>..] = [];
    var scratch2: u8[>..] = [];
    let _, ok2 = cbor::decode_with(bytes[..], opts2, values2, scratch2);
    assert(!ok2);
    // Two different keys pass the check.
    var bytes3: u8[>..] = [];
    hex_helpers::hex(bytes3, "a201020304");
    var values3: cbor::Value[>..] = [];
    var scratch3: u8[>..] = [];
    let _, ok3 = cbor::decode_with(bytes3[..], opts2, values3, scratch3);
    assert(ok3);
}

fn test_tag_check() {
    var opts = cbor::DecodeOpts { max_depth: 64, reject_dups: false, check_tags: true };
    // Tag 4 with a byte string is a wrong shape.
    var bytes: u8[>..] = [];
    hex_helpers::hex(bytes, "c44105");
    var values: cbor::Value[>..] = [];
    var scratch: u8[>..] = [];
    let _, ok = cbor::decode_with(bytes[..], opts, values, scratch);
    assert(!ok);
    // Tag 2 with a byte string is the right shape.
    var bytes2: u8[>..] = [];
    hex_helpers::hex(bytes2, "c24105");
    var values2: cbor::Value[>..] = [];
    var scratch2: u8[>..] = [];
    let _, ok2 = cbor::decode_with(bytes2[..], opts, values2, scratch2);
    assert(ok2);
    // Tag 3 with a number is a wrong shape.
    var bytes3: u8[>..] = [];
    hex_helpers::hex(bytes3, "c3010f");
    var values3: cbor::Value[>..] = [];
    var scratch3: u8[>..] = [];
    let _, ok3 = cbor::decode_with(bytes3[..], opts, values3, scratch3);
    assert(!ok3);
    // Without the flag the same bytes decode.
    var opts2 = cbor::DecodeOpts { max_depth: 64, reject_dups: false, check_tags: false };
    var values4: cbor::Value[>..] = [];
    var scratch4: u8[>..] = [];
    let _, ok4 = cbor::decode_with(bytes[..], opts2, values4, scratch4);
    assert(ok4);
}

