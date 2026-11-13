// The tests of the typed lookups, the tag numbers and the date and time values.
namespace lookup_tests;

import std;
import cbor from "..";
import hex_helpers;

fn test_typed_lookups() {
    // A map with the keys 5, -6 and a byte string.
    var bytes: u8[>..] = [];
    hex_helpers::hex(bytes, "a3050a25064361626307");
    var values: cbor::Value[>..] = [];
    var scratch: u8[>..] = [];
    let tree, ok = cbor::decode(bytes[..], values, scratch);
    assert(ok);
    let root = tree.values[tree.root];
    let v, vok = cbor::map_get_uint(tree, root, 5);
    assert(vok);
    let n, nok = cbor::as_uint(v);
    assert(nok);
    assert(n == 10);
    let v2, v2ok = cbor::map_get_int(tree, root, -6);
    assert(v2ok);
    let n2, n2ok = cbor::as_uint(v2);
    assert(n2ok);
    assert(n2 == 6);
    let v3, v3ok = cbor::map_get_bytes(tree, root, "abc");
    assert(v3ok);
    let n3, n3ok = cbor::as_uint(v3);
    assert(n3ok);
    assert(n3 == 7);
    // A text key is not found by the typed lookups.
    let _, miss = cbor::map_get_uint(tree, root, 99);
    assert(!miss);
}

fn test_tag_numbers() {
    // A bignum of 256.
    var bytes: u8[>..] = [];
    hex_helpers::hex(bytes, "c2420100");
    var values: cbor::Value[>..] = [];
    var scratch: u8[>..] = [];
    let tree, ok = cbor::decode(bytes[..], values, scratch);
    assert(ok);
    let n, nok = cbor::bignum_as_int(tree, tree.values[tree.root]);
    assert(nok);
    assert(n == 256);
    // A bignum of 2^63 does not fit an i64.
    var bytes2: u8[>..] = [];
    hex_helpers::hex(bytes2, "c2488000000000000000");
    var values2: cbor::Value[>..] = [];
    var scratch2: u8[>..] = [];
    let tree2, ok2 = cbor::decode(bytes2[..], values2, scratch2);
    assert(ok2);
    let _, nok2 = cbor::bignum_as_int(tree2, tree2.values[tree2.root]);
    assert(!nok2);
    // The bigfloat writer and its reader.
    var out: u8[>..] = [];
    cbor::encode_bigfloat(out, 1, 2);
    hex_helpers::expect_bytes(out, "c5820102");
    var values3: cbor::Value[>..] = [];
    var scratch3: u8[>..] = [];
    let tree3, ok3 = cbor::decode(out, values3, scratch3);
    assert(ok3);
    let e, m, mok = cbor::as_bigfloat(tree3, tree3.values[tree3.root]);
    assert(mok);
    assert(e == 1);
    assert(m == 2);
}

fn test_datetime_parse() {
    let e, ok = cbor::datetime_to_epoch("1970-01-01T00:00:00Z");
    assert(ok);
    assert(e == 0.0);
    let e2, ok2 = cbor::datetime_to_epoch("1970-01-02T00:00:00Z");
    assert(ok2);
    assert(e2 == 86400.0);
    // The offset shifts the value.
    let e3, ok3 = cbor::datetime_to_epoch("1970-01-01T01:00:00+01:00");
    assert(ok3);
    assert(e3 == 0.0);
    let e4, ok4 = cbor::datetime_to_epoch("2026-11-08T12:00:00Z");
    assert(ok4);
    assert(e4 > 1794000000.0);
    // A bad form faults.
    let _, ok5 = cbor::datetime_to_epoch("2026-11-08");
    assert(!ok5);
    let _, ok6 = cbor::datetime_to_epoch("2026-13-08T00:00:00Z");
    assert(!ok6);
}

