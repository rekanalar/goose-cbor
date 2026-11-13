// Tests for the cbor package. Run with: goose run test/run.goose
//
// The tests carry the RFC 8949 appendix A vectors, the acceptance
// scenarios, the fault cases and the typed API checks.

import std;
import cbor from "..";
import os;
import cbor_cases;
import hex_helpers;
import float_tests;
import hostile_tests;
import decode_option_tests;
import lookup_tests;
import canonical_tests;


fn test_rfc_vectors() {
    var out: u8[>..] = [];
    cbor::encode_uint(out, 0);
    hex_helpers::expect_bytes(out, "00");
    out = [];
    cbor::encode_uint(out, 23);
    hex_helpers::expect_bytes(out, "17");
    out = [];
    cbor::encode_uint(out, 24);
    hex_helpers::expect_bytes(out, "1818");
    out = [];
    cbor::encode_uint(out, 25);
    hex_helpers::expect_bytes(out, "1819");
    out = [];
    cbor::encode_uint(out, 100);
    hex_helpers::expect_bytes(out, "1864");
    out = [];
    cbor::encode_uint(out, 1000);
    hex_helpers::expect_bytes(out, "1903e8");
    out = [];
    cbor::encode_uint(out, 1000000);
    hex_helpers::expect_bytes(out, "1a000f4240");
    out = [];
    cbor::encode_uint(out, 18446744073709551615);
    hex_helpers::expect_bytes(out, "1bffffffffffffffff");
    out = [];
    cbor::encode_int(out, -1);
    hex_helpers::expect_bytes(out, "20");
    out = [];
    cbor::encode_int(out, -10);
    hex_helpers::expect_bytes(out, "29");
    out = [];
    cbor::encode_int(out, -1000);
    hex_helpers::expect_bytes(out, "3903e7");
    out = [];
    cbor::encode_text(out, "hi");
    hex_helpers::expect_bytes(out, "626869");
    out = [];
    cbor::encode_bool(out, true);
    hex_helpers::expect_bytes(out, "f5");
    out = [];
    cbor::encode_bool(out, false);
    hex_helpers::expect_bytes(out, "f4");
    out = [];
    cbor::encode_null(out);
    hex_helpers::expect_bytes(out, "f6");
    out = [];
    cbor::encode_float(out, 1.0);
    hex_helpers::expect_bytes(out, "f93c00");
    out = [];
    cbor::encode_float(out, 100000.0);
    hex_helpers::expect_bytes(out, "fa47c35000");
    out = [];
    cbor::encode_float(out, 1.0e300);
    hex_helpers::expect_bytes(out, "fb7e37e43c8800759c");
}

fn test_encode_array_map() {
    // [1, 2, 3] over the RFC vector: 0x83010203.
    var out: u8[>..] = [];
    cbor::encode_array_head(out, 3);
    cbor::encode_uint(out, 1);
    cbor::encode_uint(out, 2);
    cbor::encode_uint(out, 3);
    var want: u8[>..] = [];
    hex_helpers::hex(want, "83010203");
    assert(out == want[..]);

    // {"a": 1, "b": [2, 3]} over the RFC vector.
    out = [];
    cbor::encode_map_head(out, 2);
    cbor::encode_text(out, "a");
    cbor::encode_uint(out, 1);
    cbor::encode_text(out, "b");
    cbor::encode_array_head(out, 2);
    cbor::encode_uint(out, 2);
    cbor::encode_uint(out, 3);
    want = [];
    hex_helpers::hex(want, "a26161016162820203");
    assert(out == want[..]);
}

fn test_decode_rfc() {
    var n1: cbor::Value[>..] = [];
    var s1: u8[>..] = [];
    var b1: u8[>..] = [];
    let t1, ok1 = hex_helpers::decode_hex("00", b1, n1, s1);
    assert(ok1);
    let v1, f1 = cbor::as_uint(t1.values[t1.root]);
    assert(f1 && v1 == 0);

    var n2: cbor::Value[>..] = [];
    var s2: u8[>..] = [];
    var b2: u8[>..] = [];
    let t2, ok2 = hex_helpers::decode_hex("1903e8", b2, n2, s2);
    assert(ok2);
    let v2, f2 = cbor::as_uint(t2.values[t2.root]);
    assert(f2 && v2 == 1000);

    var n3: cbor::Value[>..] = [];
    var s3: u8[>..] = [];
    var b3: u8[>..] = [];
    let t3, ok3 = hex_helpers::decode_hex("626869", b3, n3, s3);
    assert(ok3);
    let v3, f3 = cbor::as_text(t3.values[t3.root]);
    assert(f3 && v3 == "hi");

    var n4: cbor::Value[>..] = [];
    var s4: u8[>..] = [];
    var b4: u8[>..] = [];
    let t4, ok4 = hex_helpers::decode_hex("20", b4, n4, s4);
    assert(ok4);
    let v4, f4 = cbor::as_int(t4.values[t4.root]);
    assert(f4 && v4 == -1);

    var n5: cbor::Value[>..] = [];
    var s5: u8[>..] = [];
    var b5: u8[>..] = [];
    let t5, ok5 = hex_helpers::decode_hex("3903e7", b5, n5, s5);
    assert(ok5);
    let v5, f5 = cbor::as_int(t5.values[t5.root]);
    assert(f5 && v5 == -1000);
}

fn test_decode_array() {
    var na: cbor::Value[>..] = [];
    var sa: u8[>..] = [];
    var b6: u8[>..] = [];
    let t, ok = hex_helpers::decode_hex("83010203", b6, na, sa);
    assert(ok);
    let root = t.values[t.root];
    assert(cbor::array_len(t, root) == 3);
    let c0, f0 = cbor::child_at(t, root, 0);
    assert(f0);
    let v0, g0 = cbor::as_uint(c0);
    assert(g0 && v0 == 1);
    let c2, f2 = cbor::child_at(t, root, 2);
    assert(f2);
    let v2, g2 = cbor::as_uint(c2);
    assert(g2 && v2 == 3);
    let c3, f3 = cbor::child_at(t, root, 3);
    assert(!f3);
}

fn test_decode_map() {
    var nm: cbor::Value[>..] = [];
    var sm: u8[>..] = [];
    var b7: u8[>..] = [];
    let t, ok = hex_helpers::decode_hex("a26161016162820203", b7, nm, sm);
    assert(ok);
    let root = t.values[t.root];
    let a_val, fa = cbor::map_get(t, root, "a");
    assert(fa);
    let av, ga = cbor::as_uint(a_val);
    assert(ga && av == 1);
    let b_val, fb = cbor::map_get(t, root, "b");
    assert(fb);
    assert(b_val.kind == cbor::K_ARRAY);
    let c, fc = cbor::child_at(t, b_val, 1);
    assert(fc);
    let cv, gc = cbor::as_uint(c);
    assert(gc && cv == 3);
}

fn test_decode_half_float() {
    // 0xf9 0x40 0x00 is 2.0.
    var nh: cbor::Value[>..] = [];
    var sh: u8[>..] = [];
    var b8: u8[>..] = [];
    let t, ok = hex_helpers::decode_hex("f94000", b8, nh, sh);
    assert(ok);
    let v, f = cbor::as_float(t.values[t.root]);
    assert(f);
    assert(v == 2.0);
}

fn test_decode_indefinite() {
    // An indefinite text of two chunks: 0x7f 0x61 0x61 0x61 0x62 0xff = "ab".
    var ni: cbor::Value[>..] = [];
    var si: u8[>..] = [];
    var b9: u8[>..] = [];
    let t, ok = hex_helpers::decode_hex("7f61616162ff", b9, ni, si);
    assert(ok);
    let v, f = cbor::as_text(t.values[t.root]);
    assert(f);
    assert(v == "ab");

    // An indefinite array: 0x9f 0x01 0x02 0xff.
    var ni2: cbor::Value[>..] = [];
    var si2: u8[>..] = [];
    var b10: u8[>..] = [];
    let t2, ok2 = hex_helpers::decode_hex("9f0102ff", b10, ni2, si2);
    assert(ok2);
    let root = t2.values[t2.root];
    assert(cbor::array_len(t2, root) == 2);
}

fn test_decode_tag() {
    // Tag 1 with uint 1000.
    var nt: cbor::Value[>..] = [];
    var st: u8[>..] = [];
    var b11: u8[>..] = [];
    let t, ok = hex_helpers::decode_hex("c11903e8", b11, nt, st);
    assert(ok);
    let root = t.values[t.root];
    assert(root.kind == cbor::K_TAG);
    assert(root.uint == 1);
    let inner, f = cbor::child_at(t, root, 0);
    assert(f);
    let v, g = cbor::as_uint(inner);
    assert(g && v == 1000);
}

fn test_faults() {
    // Input that ends inside a header.
    var b101: u8[>..] = [];
    var v201: cbor::Value[>..] = [];
    var s201: u8[>..] = [];
    var t1, ok1 = hex_helpers::decode_hex("18", b101, v201, s201);
    assert(!ok1);
    // A length the input cannot hold.
    var b102: u8[>..] = [];
    var v202: cbor::Value[>..] = [];
    var s202: u8[>..] = [];
    var t2, ok2 = hex_helpers::decode_hex("6268", b102, v202, s202);
    assert(!ok2);
    // A reserved additional-info form.
    var b103: u8[>..] = [];
    var v203: cbor::Value[>..] = [];
    var s203: u8[>..] = [];
    var t3, ok3 = hex_helpers::decode_hex("1c", b103, v203, s203);
    assert(!ok3);
    // A break byte with nothing open.
    var b104: u8[>..] = [];
    var v204: cbor::Value[>..] = [];
    var s204: u8[>..] = [];
    var t4, ok4 = hex_helpers::decode_hex("ff", b104, v204, s204);
    assert(!ok4);
    // An indefinite string with no break.
    var b105: u8[>..] = [];
    var v205: cbor::Value[>..] = [];
    var s205: u8[>..] = [];
    var t5, ok5 = hex_helpers::decode_hex("7f6161", b105, v205, s205);
    assert(!ok5);
    // An indefinite array with no break.
    var b106: u8[>..] = [];
    var v206: cbor::Value[>..] = [];
    var s206: u8[>..] = [];
    var t6, ok6 = hex_helpers::decode_hex("9f01", b106, v206, s206);
    assert(!ok6);
    // Trailing garbage.
    var b107: u8[>..] = [];
    var v207: cbor::Value[>..] = [];
    var s207: u8[>..] = [];
    var t7, ok7 = hex_helpers::decode_hex("0001", b107, v207, s207);
    assert(!ok7);
    // Empty input.
    var bytes: u8[>..] = [];
    var values: cbor::Value[>..] = [];
    var scratch: u8[>..] = [];
    var t8, ok8 = cbor::decode(bytes[..], values, scratch);
    assert(!ok8);
    // Depth beyond the cap.
    var deep: u8[>..] = [];
    var i = 0;
    while i < 70 {
        cbor::encode_array_head(deep, 2);
        cbor::encode_uint(deep, 1);
        i += 1;
    }
    i = 0;
    while i < 70 {
        deep.push(0xff);
        deep.push(0xff);
        i += 1;
    }
    var values9: cbor::Value[>..] = [];
    var scratch9: u8[>..] = [];
    var t9, ok9 = cbor::decode(deep[..], values9, scratch9);
    assert(!ok9);
}

fn test_typed_api() {
    var bytes: u8[>..] = [];
    cbor::encode_uint(bytes, 25);
    cbor::encode_text(bytes, "x");

    let v, rest, ok = cbor::read_uint(bytes[..]);
    assert(ok && v == 25);
    let t, rrest, tok = cbor::read_text(rest);
    assert(tok && t == "x");
    assert(rrest.len == 0);

    // A type mismatch faults.
    let b, rb, bok = cbor::read_bool(bytes[..]);
    assert(!bok);

    var fbytes: u8[>..] = [];
    cbor::encode_float(fbytes, 2.5);
    let fv, ffv, fok = cbor::read_float(fbytes[..]);
    assert(fok);
    assert(fv == 2.5);

    var nul: u8[>..] = [];
    cbor::encode_null(nul);
    let rnul, nok = cbor::read_null(nul[..]);
    assert(nok && rnul.len == 0);

    // A uint also reads as an int; a text does not.
    let iv, ir, iok = cbor::read_int(bytes[..]);
    assert(iok && iv == 25);
}

fn test_roundtrip_tree() {
    var bytes: u8[>..] = [];
    cbor::encode_map_head(bytes, 2);
    cbor::encode_text(bytes, "name");
    cbor::encode_text(bytes, "goose");
    cbor::encode_text(bytes, "nums");
    cbor::encode_array_head(bytes, 3);
    cbor::encode_int(bytes, -5);
    cbor::encode_uint(bytes, 42);
    cbor::encode_bool(bytes, true);

    var values: cbor::Value[>..] = [];
    var scratch: u8[>..] = [];
    let t, ok = cbor::decode(bytes[..], values, scratch);
    assert(ok);
    let root = t.values[t.root];
    let name, f1 = cbor::map_get(t, root, "name");
    assert(f1);
    let nv, g1 = cbor::as_text(name);
    assert(g1 && nv == "goose");
    let nums, f2 = cbor::map_get(t, root, "nums");
    assert(f2);
    let n0, g2 = cbor::child_at(t, nums, 0);
    assert(g2);
    let n0v, g3 = cbor::as_int(n0);
    assert(g3 && n0v == -5);
    let n1, g4 = cbor::child_at(t, nums, 1);
    assert(g4);
    let n1v, g5 = cbor::as_uint(n1);
    assert(g5 && n1v == 42);
    let n2, g6 = cbor::child_at(t, nums, 2);
    assert(g6);
    let n2v, g7 = cbor::as_bool(n2);
    assert(g7 && n2v);
}

fn test_large_document() {
    var bytes: u8[>..] = [];
    // One array of 20000 uint/text pairs: about 1 MiB total.
    cbor::encode_array_head(bytes, 40000);
    var i: u64 = 0;
    while i < 20000 {
        cbor::encode_uint(bytes, i);
        cbor::encode_text(bytes, "0123456789abcdef0123456789abcdef");
        i += 1;
    }
    var values: cbor::Value[>..] = [];
    var scratch: u8[>..] = [];
    let t, ok = cbor::decode(bytes[..], values, scratch);
    assert(ok);
    let root = t.values[t.root];
    assert(root.kind == cbor::K_ARRAY);
    assert(cbor::array_len(t, root) == 40000);
}

fn test_int_limits() {
    var out: u8[>..] = [];
    cbor::encode_int(out, -9223372036854775807 - 1);
    hex_helpers::expect_bytes(out, "3b7fffffffffffffff");
    let v, rest, ok = cbor::read_int(out[..]);
    assert(ok && v == -9223372036854775807 - 1);
    // -2^64 is beyond i64: the read faults.
    var big: u8[>..] = [];
    hex_helpers::hex(big, "3bffffffffffffffff");
    let v2, rest2, ok2 = cbor::read_int(big[..]);
    assert(!ok2);
}

// The RFC 8949 section 4.2.1 key order: 10, 100, -1, "z", "aa", [100],
// [-1], false. The test writes them in the reverse order.
fn test_sorted_map() {
    var out: u8[>..] = [];
    var tmp: u8[>..] = [];
    cbor::encode_map_head(out, 8);
    let start = out.len;
    cbor::encode_bool(out, false);
    cbor::encode_uint(out, 8);
    cbor::encode_array_head(out, 1);
    cbor::encode_int(out, -1);
    cbor::encode_uint(out, 7);
    cbor::encode_array_head(out, 1);
    cbor::encode_uint(out, 100);
    cbor::encode_uint(out, 6);
    cbor::encode_text(out, "aa");
    cbor::encode_uint(out, 5);
    cbor::encode_text(out, "z");
    cbor::encode_uint(out, 4);
    cbor::encode_int(out, -1);
    cbor::encode_uint(out, 3);
    cbor::encode_uint(out, 100);
    cbor::encode_uint(out, 2);
    cbor::encode_uint(out, 10);
    cbor::encode_uint(out, 1);
    assert(cbor::sort_map(out, start, 8, tmp));
    hex_helpers::expect_bytes(out, "a80a011864022003617a046261610581186406812007f408");

    // The RFC example map {"a": 1, "b": [2, 3]} written in reverse.
    out = [];
    tmp = [];
    cbor::encode_map_head(out, 2);
    let s2 = out.len;
    cbor::encode_text(out, "b");
    cbor::encode_array_head(out, 2);
    cbor::encode_uint(out, 2);
    cbor::encode_uint(out, 3);
    cbor::encode_text(out, "a");
    cbor::encode_uint(out, 1);
    assert(cbor::sort_map(out, s2, 2, tmp));
    hex_helpers::expect_bytes(out, "a26161016162820203");

    // A nested map sorts first, then the outer map.
    out = [];
    tmp = [];
    cbor::encode_map_head(out, 2);
    let s3 = out.len;
    cbor::encode_text(out, "b");
    cbor::encode_map_head(out, 2);
    let s4 = out.len;
    cbor::encode_text(out, "y");
    cbor::encode_uint(out, 1);
    cbor::encode_text(out, "x");
    cbor::encode_uint(out, 2);
    assert(cbor::sort_map(out, s4, 2, tmp));
    cbor::encode_text(out, "a");
    cbor::encode_uint(out, 0);
    tmp = [];
    assert(cbor::sort_map(out, s3, 2, tmp));
    hex_helpers::expect_bytes(out, "a26161006162a2617802617901");

    // A wrong pair count gives false and leaves the bytes alone.
    out = [];
    tmp = [];
    cbor::encode_map_head(out, 2);
    let s5 = out.len;
    cbor::encode_uint(out, 1);
    cbor::encode_uint(out, 2);
    assert(!cbor::sort_map(out, s5, 2, tmp));
}

fn test_named_tags() {
    var out: u8[>..] = [];
    cbor::encode_datetime_string(out, "2013-03-21T20:04:00Z");
    hex_helpers::expect_bytes(out, "c074323031332d30332d32315432303a30343a30305a");
    out = [];
    cbor::encode_epoch(out, 1363896240);
    hex_helpers::expect_bytes(out, "c11a514b67b0");
    out = [];
    cbor::encode_epoch_float(out, 1363896240.5);
    hex_helpers::expect_bytes(out, "c1fb41d452d9ec200000");
    out = [];
    cbor::encode_decimal(out, -2, 27315);
    hex_helpers::expect_bytes(out, "c48221196ab3");
    // 2^64 and -2^64-1, with a leading zero byte that drops away.
    var mag: u8[>..] = [];
    hex_helpers::hex(mag, "00010000000000000000");
    out = [];
    cbor::encode_bignum(out, false, mag[..]);
    hex_helpers::expect_bytes(out, "c249010000000000000000");
    out = [];
    cbor::encode_bignum(out, true, mag[..]);
    hex_helpers::expect_bytes(out, "c349010000000000000000");
    // A small magnitude uses the plain integer form.
    var small: u8[>..] = [0, 0, 1, 0];
    out = [];
    cbor::encode_bignum(out, false, small[..]);
    hex_helpers::expect_bytes(out, "190100");
    out = [];
    cbor::encode_bignum(out, true, small[..]);
    hex_helpers::expect_bytes(out, "390100");

    // The accessors read them back.
    var v: cbor::Value[>..] = [];
    var s: u8[>..] = [];
    var b: u8[>..] = [];
    let t, ok = hex_helpers::decode_hex("c1fb41d452d9ec200000", b, v, s);
    assert(ok);
    let tn, istag = cbor::as_tag(t.values[t.root]);
    assert(istag && tn == cbor::TAG_EPOCH);
    let secs, isep = cbor::as_epoch(t, t.values[t.root]);
    assert(isep && secs == 1363896240.5);
    var v2: cbor::Value[>..] = [];
    var s2: u8[>..] = [];
    var b2: u8[>..] = [];
    let t2, ok2 = hex_helpers::decode_hex("c249010000000000000000", b2, v2, s2);
    assert(ok2);
    let neg, m, isbig = cbor::as_bignum(t2, t2.values[t2.root]);
    assert(isbig && !neg && m.len == 9 && m[0] == 1);
    var v3: cbor::Value[>..] = [];
    var s3: u8[>..] = [];
    var b3: u8[>..] = [];
    let t3, ok3 = hex_helpers::decode_hex("c074323031332d30332d32315432303a30343a30305a", b3, v3, s3);
    assert(ok3);
    let txt, isdt = cbor::as_datetime_string(t3, t3.values[t3.root]);
    assert(isdt && txt == "2013-03-21T20:04:00Z");
    // A different tag is not a date.
    let none, notdt = cbor::as_datetime_string(t, t.values[t.root]);
    assert(!notdt);
}

fn test_cbor_cases() {
    cbor_cases::check_decode();
    cbor_cases::check_encode();
}

fn main() {
    test_rfc_vectors();
    test_encode_array_map();
    test_decode_rfc();
    test_decode_array();
    test_decode_map();
    test_decode_half_float();
    test_decode_indefinite();
    test_decode_tag();
    test_faults();
    test_typed_api();
    test_roundtrip_tree();
    test_large_document();
    float_tests::test_shortest_float();
    float_tests::test_float_edges();
    float_tests::test_decode_single_float();
    test_int_limits();
    test_sorted_map();
    test_named_tags();
    hostile_tests::test_probe();
    hostile_tests::test_len31();
    hostile_tests::test_hostile();
    test_cbor_cases();
    decode_option_tests::test_decode_first();
    decode_option_tests::test_depth_option();
    decode_option_tests::test_duplicate_keys();
    decode_option_tests::test_tag_check();
    canonical_tests::test_rfc7049_sort();
    lookup_tests::test_typed_lookups();
    lookup_tests::test_tag_numbers();
    lookup_tests::test_datetime_parse();
    canonical_tests::test_canonical_check();
    canonical_tests::test_cbor2_cases();
    print("all tests passed");
    return 0;
}
