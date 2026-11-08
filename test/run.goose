// Tests for the cbor package. Run with: goose run test/run.goose
//
// The tests carry the RFC 8949 appendix A vectors, the acceptance
// scenarios, the fault cases and the typed API checks.

import std;
import cbor from "..";
import os;
import cbor_cases;
import cbor2_cases;

// hex reads one hex string into a builder.
fn hex(out: u8[>..]&, s: const u8[:]) {
    var i: i64 = 0;
    while i + 1 < s.len {
        let hi, ok1 = hex_digit(s[i]);
        let lo, ok2 = hex_digit(s[i + 1]);
        assert(ok1 && ok2);
        out.push((hi * 16 + lo) as u8);
        i += 2;
    }
}

fn hex_digit(c: u8) -> i32, bool {
    if c >= '0' && c <= '9' { return c - '0', true; }
    if c >= 'a' && c <= 'f' { return c - 'a' + 10, true; }
    if c >= 'A' && c <= 'F' { return c - 'A' + 10, true; }
    return -1, false;
}

fn to_bytes(out: u8[>..]&, s: const u8[:]) {
    hex(out, s);
}

// expect_vec encodes one vector with a builder fn body inlined below.
fn expect_bytes(out: u8[>..]&, want_hex: const u8[:]) {
    var want: u8[>..] = [];
    hex(want, want_hex);
    if out != want[..] {
        print("VECTOR FAIL want=", want_hex, " got_len=", out.len);
        var i: i64 = 0;
        while i < out.len {
            print(out[i], " ");
            i += 1;
        }
        print("");
        assert(out == want[..]);
    }
}

// decode_hex decodes one hex string into the buffers of the caller.
// The bytes buffer holds the input, and the spans in the tree point
// into it, so it must outlive the tree.
fn decode_hex(s: const u8[:], bytes: u8[>..]&, values: cbor::Value[>..]&, scratch: u8[>..]&) -> cbor::Tree, bool {
    hex(bytes, s);
    return cbor::decode(bytes[..], values, scratch);
}

fn test_rfc_vectors() {
    var out: u8[>..] = [];
    cbor::encode_uint(out, 0);
    expect_bytes(out, "00");
    out = [];
    cbor::encode_uint(out, 23);
    expect_bytes(out, "17");
    out = [];
    cbor::encode_uint(out, 24);
    expect_bytes(out, "1818");
    out = [];
    cbor::encode_uint(out, 25);
    expect_bytes(out, "1819");
    out = [];
    cbor::encode_uint(out, 100);
    expect_bytes(out, "1864");
    out = [];
    cbor::encode_uint(out, 1000);
    expect_bytes(out, "1903e8");
    out = [];
    cbor::encode_uint(out, 1000000);
    expect_bytes(out, "1a000f4240");
    out = [];
    cbor::encode_uint(out, 18446744073709551615);
    expect_bytes(out, "1bffffffffffffffff");
    out = [];
    cbor::encode_int(out, -1);
    expect_bytes(out, "20");
    out = [];
    cbor::encode_int(out, -10);
    expect_bytes(out, "29");
    out = [];
    cbor::encode_int(out, -1000);
    expect_bytes(out, "3903e7");
    out = [];
    cbor::encode_text(out, "hi");
    expect_bytes(out, "626869");
    out = [];
    cbor::encode_bool(out, true);
    expect_bytes(out, "f5");
    out = [];
    cbor::encode_bool(out, false);
    expect_bytes(out, "f4");
    out = [];
    cbor::encode_null(out);
    expect_bytes(out, "f6");
    out = [];
    cbor::encode_float(out, 1.0);
    expect_bytes(out, "f93c00");
    out = [];
    cbor::encode_float(out, 100000.0);
    expect_bytes(out, "fa47c35000");
    out = [];
    cbor::encode_float(out, 1.0e300);
    expect_bytes(out, "fb7e37e43c8800759c");
}

fn test_encode_array_map() {
    // [1, 2, 3] over the RFC vector: 0x83010203.
    var out: u8[>..] = [];
    cbor::encode_array_head(out, 3);
    cbor::encode_uint(out, 1);
    cbor::encode_uint(out, 2);
    cbor::encode_uint(out, 3);
    var want: u8[>..] = [];
    hex(want, "83010203");
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
    hex(want, "a26161016162820203");
    assert(out == want[..]);
}

fn test_decode_rfc() {
    var n1: cbor::Value[>..] = [];
    var s1: u8[>..] = [];
    var b1: u8[>..] = [];
    let t1, ok1 = decode_hex("00", b1, n1, s1);
    assert(ok1);
    let v1, f1 = cbor::as_uint(t1.values[t1.root]);
    assert(f1 && v1 == 0);

    var n2: cbor::Value[>..] = [];
    var s2: u8[>..] = [];
    var b2: u8[>..] = [];
    let t2, ok2 = decode_hex("1903e8", b2, n2, s2);
    assert(ok2);
    let v2, f2 = cbor::as_uint(t2.values[t2.root]);
    assert(f2 && v2 == 1000);

    var n3: cbor::Value[>..] = [];
    var s3: u8[>..] = [];
    var b3: u8[>..] = [];
    let t3, ok3 = decode_hex("626869", b3, n3, s3);
    assert(ok3);
    let v3, f3 = cbor::as_text(t3.values[t3.root]);
    assert(f3 && v3 == "hi");

    var n4: cbor::Value[>..] = [];
    var s4: u8[>..] = [];
    var b4: u8[>..] = [];
    let t4, ok4 = decode_hex("20", b4, n4, s4);
    assert(ok4);
    let v4, f4 = cbor::as_int(t4.values[t4.root]);
    assert(f4 && v4 == -1);

    var n5: cbor::Value[>..] = [];
    var s5: u8[>..] = [];
    var b5: u8[>..] = [];
    let t5, ok5 = decode_hex("3903e7", b5, n5, s5);
    assert(ok5);
    let v5, f5 = cbor::as_int(t5.values[t5.root]);
    assert(f5 && v5 == -1000);
}

fn test_decode_array() {
    var na: cbor::Value[>..] = [];
    var sa: u8[>..] = [];
    var b6: u8[>..] = [];
    let t, ok = decode_hex("83010203", b6, na, sa);
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
    let t, ok = decode_hex("a26161016162820203", b7, nm, sm);
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
    let t, ok = decode_hex("f94000", b8, nh, sh);
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
    let t, ok = decode_hex("7f61616162ff", b9, ni, si);
    assert(ok);
    let v, f = cbor::as_text(t.values[t.root]);
    assert(f);
    assert(v == "ab");

    // An indefinite array: 0x9f 0x01 0x02 0xff.
    var ni2: cbor::Value[>..] = [];
    var si2: u8[>..] = [];
    var b10: u8[>..] = [];
    let t2, ok2 = decode_hex("9f0102ff", b10, ni2, si2);
    assert(ok2);
    let root = t2.values[t2.root];
    assert(cbor::array_len(t2, root) == 2);
}

fn test_decode_tag() {
    // Tag 1 with uint 1000.
    var nt: cbor::Value[>..] = [];
    var st: u8[>..] = [];
    var b11: u8[>..] = [];
    let t, ok = decode_hex("c11903e8", b11, nt, st);
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
    var t1, ok1 = decode_hex("18", b101, v201, s201);
    assert(!ok1);
    // A length the input cannot hold.
    var b102: u8[>..] = [];
    var v202: cbor::Value[>..] = [];
    var s202: u8[>..] = [];
    var t2, ok2 = decode_hex("6268", b102, v202, s202);
    assert(!ok2);
    // A reserved additional-info form.
    var b103: u8[>..] = [];
    var v203: cbor::Value[>..] = [];
    var s203: u8[>..] = [];
    var t3, ok3 = decode_hex("1c", b103, v203, s203);
    assert(!ok3);
    // A break byte with nothing open.
    var b104: u8[>..] = [];
    var v204: cbor::Value[>..] = [];
    var s204: u8[>..] = [];
    var t4, ok4 = decode_hex("ff", b104, v204, s204);
    assert(!ok4);
    // An indefinite string with no break.
    var b105: u8[>..] = [];
    var v205: cbor::Value[>..] = [];
    var s205: u8[>..] = [];
    var t5, ok5 = decode_hex("7f6161", b105, v205, s205);
    assert(!ok5);
    // An indefinite array with no break.
    var b106: u8[>..] = [];
    var v206: cbor::Value[>..] = [];
    var s206: u8[>..] = [];
    var t6, ok6 = decode_hex("9f01", b106, v206, s206);
    assert(!ok6);
    // Trailing garbage.
    var b107: u8[>..] = [];
    var v207: cbor::Value[>..] = [];
    var s207: u8[>..] = [];
    var t7, ok7 = decode_hex("0001", b107, v207, s207);
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


// float_case encodes v in the shortest form, checks the RFC bytes, then
// decodes them and checks the value comes back.
fn float_case(v: f64, want_hex: const u8[:]) {
    var out: u8[>..] = [];
    cbor::encode_float(out, v);
    expect_bytes(out, want_hex);
    let back, rest, ok = cbor::read_float(out[..]);
    assert(ok && rest.len == 0);
    if v == v { assert(back == v); } else { assert(back != back); }
}

// pos_inf builds +infinity with a loop of doublings. The TinyCC JIT on
// macOS/arm64 mis-evaluates 1.0 / 0.0, so the tests never divide by
// zero.
fn pos_inf() -> f64 {
    var p: f64 = 1.0;
    var i: i64 = 0;
    while i < 1024 { p = p * 2.0; i += 1; }
    return p;
}

fn neg_inf() -> f64 { return -pos_inf(); }

fn nan_value() -> f64 { return pos_inf() - pos_inf(); }

fn test_shortest_float() {
    // RFC 8949 appendix A.
    float_case(0.0, "f90000");
    float_case(-0.0, "f98000");
    float_case(1.0, "f93c00");
    float_case(1.1, "fb3ff199999999999a");
    float_case(1.5, "f93e00");
    float_case(65504.0, "f97bff");
    float_case(100000.0, "fa47c35000");
    float_case(3.4028234663852886e+38, "fa7f7fffff");
    float_case(1.0e+300, "fb7e37e43c8800759c");
    float_case(5.960464477539063e-8, "f90001");
    float_case(0.00006103515625, "f90400");
    float_case(-4.0, "f9c400");
    float_case(-4.1, "fbc010666666666666");
    float_case(pos_inf(), "f97c00");
    float_case(neg_inf(), "f9fc00");
    float_case(nan_value(), "f97e00");    // RFC 8949 section 4.1 examples.
    float_case(5.5, "f94580");
    float_case(5555.5, "fa45ad9c00");
    float_case(1000000.5, "fa49742408");
    // Just past the half range and a f32 subnormal.
    float_case(65536.0, "fa47800000");
    float_case(1.401298464324817e-45, "fa00000001");
    float_case(5e-324, "fb0000000000000001");
    // The full form stays on request.
    var out: u8[>..] = [];
    cbor::encode_float64(out, 1.0);
    expect_bytes(out, "fb3ff0000000000000");
    out = [];
    cbor::encode_float64(out, nan_value());
    expect_bytes(out, "fb7ff8000000000000");
}

// The edge values of the float formats, checked against the bytes that
// Python's cbor2 writes for the same values and against the tables of
// RFC 8949 appendix A.
fn test_float_edges() {
    float_case(0.0, "f90000");
    float_case(-0.0, "f98000");
    // The smallest normal half: 2^-14.
    float_case(0.00006103515625, "f90400");
    // The largest normal half.
    float_case(65504.0, "f97bff");
    // The smallest subnormal half: 2^-24.
    float_case(5.960464477539063e-8, "f90001");
    float_case(1.0, "f93c00");
    float_case(-1.0, "f9bc00");
    float_case(2.5, "f94100");
    // The largest half subnormal, and a half subnormal one ulp below.
    float_case(6.097555160522461e-05, "f903ff");
    float_case(5.91278076171875e-05, "f903e0");
    // A single subnormal.
    float_case(1.401298464324817e-45, "fa00000001");
    // The largest single.
    float_case(3.4028234663852886e+38, "fa7f7fffff");
    // Values that no short form holds exactly.
    float_case(1.0e300, "fb7e37e43c8800759c");
    float_case(1.0e-300, "fb01a56e1fc2f8f359");
    float_case(1e-5, "fb3ee4f8b588e368f1");
    // The smallest positive double subnormal.
    float_case(5e-324, "fb0000000000000001");
    // A value just past the half range, on the single path.
    float_case(65520.0, "fa477ff000");
    float_case(pos_inf(), "f97c00");
    float_case(neg_inf(), "f9fc00");
    float_case(nan_value(), "f97e00");
}

fn test_decode_single_float() {
    // RFC 8949 appendix A: 0xfa47c35000 is 100000.0, 0xfa7f7fffff is max f32.
    var v: cbor::Value[>..] = [];
    var s: u8[>..] = [];
    var b: u8[>..] = [];
    let t, ok = decode_hex("fa47c35000", b, v, s);
    assert(ok);
    let f, g = cbor::as_float(t.values[t.root]);
    assert(g && f == 100000.0);
    var v2: cbor::Value[>..] = [];
    var s2: u8[>..] = [];
    var b2: u8[>..] = [];
    let t2, ok2 = decode_hex("fa7f7fffff", b2, v2, s2);
    assert(ok2);
    let f2, g2 = cbor::as_float(t2.values[t2.root]);
    assert(g2 && f2 == 3.4028234663852886e+38);
}

fn test_int_limits() {
    var out: u8[>..] = [];
    cbor::encode_int(out, -9223372036854775807 - 1);
    expect_bytes(out, "3b7fffffffffffffff");
    let v, rest, ok = cbor::read_int(out[..]);
    assert(ok && v == -9223372036854775807 - 1);
    // -2^64 is beyond i64: the read faults.
    var big: u8[>..] = [];
    hex(big, "3bffffffffffffffff");
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
    expect_bytes(out, "a80a011864022003617a046261610581186406812007f408");

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
    expect_bytes(out, "a26161016162820203");

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
    expect_bytes(out, "a26161006162a2617802617901");

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
    expect_bytes(out, "c074323031332d30332d32315432303a30343a30305a");
    out = [];
    cbor::encode_epoch(out, 1363896240);
    expect_bytes(out, "c11a514b67b0");
    out = [];
    cbor::encode_epoch_float(out, 1363896240.5);
    expect_bytes(out, "c1fb41d452d9ec200000");
    out = [];
    cbor::encode_decimal(out, -2, 27315);
    expect_bytes(out, "c48221196ab3");
    // 2^64 and -2^64-1, with a leading zero byte that drops away.
    var mag: u8[>..] = [];
    hex(mag, "00010000000000000000");
    out = [];
    cbor::encode_bignum(out, false, mag[..]);
    expect_bytes(out, "c249010000000000000000");
    out = [];
    cbor::encode_bignum(out, true, mag[..]);
    expect_bytes(out, "c349010000000000000000");
    // A small magnitude uses the plain integer form.
    var small: u8[>..] = [0, 0, 1, 0];
    out = [];
    cbor::encode_bignum(out, false, small[..]);
    expect_bytes(out, "190100");
    out = [];
    cbor::encode_bignum(out, true, small[..]);
    expect_bytes(out, "390100");

    // The accessors read them back.
    var v: cbor::Value[>..] = [];
    var s: u8[>..] = [];
    var b: u8[>..] = [];
    let t, ok = decode_hex("c1fb41d452d9ec200000", b, v, s);
    assert(ok);
    let tn, istag = cbor::as_tag(t.values[t.root]);
    assert(istag && tn == cbor::TAG_EPOCH);
    let secs, isep = cbor::as_epoch(t, t.values[t.root]);
    assert(isep && secs == 1363896240.5);
    var v2: cbor::Value[>..] = [];
    var s2: u8[>..] = [];
    var b2: u8[>..] = [];
    let t2, ok2 = decode_hex("c249010000000000000000", b2, v2, s2);
    assert(ok2);
    let neg, m, isbig = cbor::as_bignum(t2, t2.values[t2.root]);
    assert(isbig && !neg && m.len == 9 && m[0] == 1);
    var v3: cbor::Value[>..] = [];
    var s3: u8[>..] = [];
    var b3: u8[>..] = [];
    let t3, ok3 = decode_hex("c074323031332d30332d32315432303a30343a30305a", b3, v3, s3);
    assert(ok3);
    let txt, isdt = cbor::as_datetime_string(t3, t3.values[t3.root]);
    assert(isdt && txt == "2013-03-21T20:04:00Z");
    // A different tag is not a date.
    let none, notdt = cbor::as_datetime_string(t, t.values[t.root]);
    assert(!notdt);
}

// probe decodes one hex input and checks the answer. The inputs are the
// 97 of the audit, with the answer of cbor2 and fxamacker/cbor. Six answers
// are the stated limits of this package: trailing bytes, the lazy tag
// checks and the depth limit.
fn probe(name: const u8[:], h: const u8[:], want_ok: bool) {
    var bytes: u8[>..] = [];
    hex(bytes, h);
    var values: cbor::Value[>..] = [];
    var scratch: u8[>..] = [];
    let t, ok = cbor::decode(bytes[..], values, scratch);
    if ok != want_ok {
        print("PROBE FAIL ", name, " want ", want_ok, " got ", ok);
        assert(false);
    }
}

fn test_probe() {
    probe("simple-e0", "e0", true);
    probe("simple-e1", "e1", true);
    probe("simple-e2", "e2", true);
    probe("simple-e3", "e3", true);
    probe("simple-e4", "e4", true);
    probe("simple-e5", "e5", true);
    probe("simple-e6", "e6", true);
    probe("simple-e7", "e7", true);
    probe("simple-e8", "e8", true);
    probe("simple-e9", "e9", true);
    probe("simple-ea", "ea", true);
    probe("simple-eb", "eb", true);
    probe("simple-ec", "ec", true);
    probe("simple-ed", "ed", true);
    probe("simple-ee", "ee", true);
    probe("simple-ef", "ef", true);
    probe("simple-f0", "f0", true);
    probe("simple-f1", "f1", true);
    probe("simple-f2", "f2", true);
    probe("simple-f3", "f3", true);
    probe("simple-fc", "fc", false);
    probe("simple-fd", "fd", false);
    probe("simple-fe", "fe", false);
    probe("simple2-0", "f800", false);
    probe("simple2-19", "f813", false);
    probe("simple2-20", "f814", false);
    probe("simple2-23", "f817", false);
    probe("simple2-24", "f818", false);
    probe("simple2-31", "f81f", false);
    probe("simple2-32", "f820", true);
    probe("simple2-255", "f8ff", true);
    probe("undefined", "f7", true);
    probe("null", "f6", true);
    probe("true", "f5", true);
    probe("false", "f4", true);
    probe("break-alone", "ff", false);
    probe("indef-array", "9f0102ff", true);
    probe("indef-array-empty", "9fff", true);
    probe("indef-array-nobreak", "9f01", false);
    probe("indef-bytes", "5f4101420203ff", true);
    probe("indef-bytes-bad-chunk", "5f6161ff", false);
    probe("indef-text", "7f61616162ff", true);
    probe("indef-text-bad-chunk", "7f4161ff", false);
    probe("indef-map", "bf616101ff", true);
    probe("indef-map-oddkey", "bf6161ff", false);
    probe("indef-nested", "9f9f01ffff", true);
    probe("indef-uint", "1f", false);
    probe("indef-neg", "3f", false);
    probe("indef-tag", "df", false);
    probe("reserved-28", "1c", false);
    probe("reserved-29", "1d", false);
    probe("reserved-30", "1e", false);
    probe("reserved-arr-28", "9c", false);
    probe("reserved-map-30", "be", false);
    probe("trunc-arr", "8201", false);
    probe("trunc-uint", "19ff", false);
    probe("trunc-text", "6461", false);
    probe("trunc-bytes", "4401", false);
    probe("trunc-map", "a16161", false);
    probe("trunc-tag", "c1", false);
    probe("trailing", "0001", false);
    probe("tag-nested", "c1c101", true);
    probe("tag-0-text", "c074323031332d30332d32315432303a30343a30305a", true);
    probe("tag-0-int", "c001", true);
    probe("tag-1-int", "c11a514b67b0", true);
    probe("tag-1-text", "c16161", true);
    probe("tag-2", "c249010000000000000000", true);
    probe("tag-3", "c349010000000000000000", true);
    probe("tag-2-int", "c201", true);
    probe("tag-4", "c48221196ab3", true);
    probe("tag-4-bad", "c4821901", false);
    probe("tag-55799", "d9d9f701", true);
    probe("tag-big", "dbffffffffffffffff01", true);
    probe("dup-key", "a2616101616102", true);
    probe("dup-key-int", "a201010201", true);
    probe("half-sub", "f90001", true);
    probe("half-max", "f97bff", true);
    probe("half-nan", "f97e00", true);
    probe("half-nan-payload", "f97e01", true);
    probe("half-inf", "f97c00", true);
    probe("half-neginf", "f9fc00", true);
    probe("half-negzero", "f98000", true);
    probe("single-nan-payload", "fa7fc00001", true);
    probe("double-nan-payload", "fb7ff8000000000001", true);
    probe("utf8-bad", "62c328", false);
    probe("utf8-overlong", "63e08080", false);
    probe("utf8-surrogate", "63eda080", false);
    probe("uint-nonpref", "1800", true);
    probe("uint-nonpref2", "190001", true);
    probe("map-nontext-key", "a182010201", true);
    probe("len-huge", "5bffffffffffffffff", false);
    probe("arr-huge", "9bffffffffffffffff", false);
    probe("text-huge", "7b7fffffffffffffff", false);
    probe("empty", "", false);

    // The depth limit is 64: 64 levels pass and 65 levels fail.
    var d64: u8[>..] = [];
    for i in 0..64 { d64.push(0x81); }
    d64.push(0x00);
    var v64: cbor::Value[>..] = [];
    var s64: u8[>..] = [];
    let t64, ok64 = cbor::decode(d64[..], v64, s64);
    assert(ok64);
    var d65: u8[>..] = [];
    for i in 0..65 { d65.push(0x81); }
    d65.push(0x00);
    var v65: cbor::Value[>..] = [];
    var s65: u8[>..] = [];
    let t65, ok65 = cbor::decode(d65[..], v65, s65);
    assert(!ok65);
}

// refuse_bytes checks that one input gives false and does not abort.
fn refuse_bytes(b: const u8[:]) {
    var values: cbor::Value[>..] = [];
    var scratch: u8[>..] = [];
    let t, ok = cbor::decode(b, values, scratch);
    assert(!ok);
}

fn accept_bytes(b: const u8[:]) {
    var values: cbor::Value[>..] = [];
    var scratch: u8[>..] = [];
    let t, ok = cbor::decode(b, values, scratch);
    assert(ok);
}

// test_hostile feeds the decoder inputs that declare more than they hold.
// None may abort and the whole set must finish in under one second.
fn test_hostile() {
    let t0 = clock_ns();
    var b: u8[>..] = [];

    // Byte and text strings with a very large length.
    hex(b, "5bffffffffffffffff"); refuse_bytes(b[..]); b = [];
    hex(b, "5b8000000000000000"); refuse_bytes(b[..]); b = [];
    hex(b, "5b7fffffffffffffff"); refuse_bytes(b[..]); b = [];
    hex(b, "7bffffffffffffffff"); refuse_bytes(b[..]); b = [];
    hex(b, "7b7fffffffffffffff"); refuse_bytes(b[..]); b = [];
    hex(b, "5a7fffffff"); refuse_bytes(b[..]); b = [];
    // A length that fits exactly passes. One byte more fails.
    hex(b, "450102030405"); accept_bytes(b[..]); b = [];
    hex(b, "46010203040506"); accept_bytes(b[..]); b = [];
    hex(b, "4601020304"); refuse_bytes(b[..]); b = [];
    // A chunk of an indefinite string with a very large length.
    hex(b, "5f5bffffffffffffffffff"); refuse_bytes(b[..]); b = [];
    hex(b, "7f7b7fffffffffffffffff"); refuse_bytes(b[..]); b = [];

    // Array and map counts above the bytes left, and counts that look like the
    // sentinel value after a signed cast.
    hex(b, "9bffffffffffffffff"); refuse_bytes(b[..]); b = [];
    hex(b, "9b8000000000000000"); refuse_bytes(b[..]); b = [];
    hex(b, "9b8000000000000000ff"); refuse_bytes(b[..]); b = [];
    hex(b, "bbffffffffffffffff"); refuse_bytes(b[..]); b = [];
    hex(b, "bb8000000000000000"); refuse_bytes(b[..]); b = [];
    hex(b, "9affffffff"); refuse_bytes(b[..]); b = [];
    hex(b, "9a000000050102"); refuse_bytes(b[..]); b = [];
    hex(b, "a2616101"); refuse_bytes(b[..]); b = [];

    // 100000 levels of nesting fail at the depth limit.
    var deep: u8[>..] = [];
    for i in 0..100000 { deep.push(0x81); }
    deep.push(0x00);
    refuse_bytes(deep[..]);

    // One array of 100000 empty arrays, and one of 100000 integers.
    var wide: u8[>..] = [];
    hex(wide, "9a000186a0");
    for i in 0..100000 { wide.push(0x80); }
    accept_bytes(wide[..]);
    var ints: u8[>..] = [];
    ints.push(0x9f);
    for i in 0..100000 { ints.push(0x01); }
    ints.push(0xff);
    accept_bytes(ints[..]);

    // An indefinite text string of 100000 chunks.
    var chunks: u8[>..] = [];
    chunks.push(0x7f);
    for i in 0..100000 { chunks.push(0x61); chunks.push(0x61); }
    chunks.push(0xff);
    accept_bytes(chunks[..]);

    assert(clock_ns() - t0 < 1000000000);
}

// test_len31 checks the one-byte head with the length 31. The value 31 is
// also the marker of an indefinite head, so a definite item must not read as one.
fn test_len31() {
    var b: u8[>..] = [];
    hex(b, "581f");
    for i in 0..31 { b.push('x'); }
    accept_bytes(b[..]);
    var t: u8[>..] = [];
    hex(t, "781f");
    for i in 0..31 { t.push('y'); }
    accept_bytes(t[..]);
    var a: u8[>..] = [];
    hex(a, "981f");
    for i in 0..31 { a.push(0x01); }
    accept_bytes(a[..]);
    var m: u8[>..] = [];
    hex(m, "b81f");
    for i in 0..31 { m.push(0x01); m.push(0x02); }
    accept_bytes(m[..]);
    // A chunk of 31 bytes in an indefinite string.
    var c: u8[>..] = [];
    hex(c, "5f581f");
    for i in 0..31 { c.push('z'); }
    c.push(0xff);
    accept_bytes(c[..]);
    // One byte short is a fault.
    var s: u8[>..] = [];
    hex(s, "581f");
    for i in 0..30 { s.push('x'); }
    refuse_bytes(s[..]);
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
    test_shortest_float();
    test_float_edges();
    test_decode_single_float();
    test_int_limits();
    test_sorted_map();
    test_named_tags();
    test_probe();
    test_len31();
    test_hostile();
    test_cbor_cases();

// The v1.0.0 stories: US1 to US8.

fn test_decode_first() {
    var bytes: u8[>..] = [];
    hex(bytes, "0102");
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
    hex(bytes, "a201020103");
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
    hex(bytes3, "a201020304");
    var values3: cbor::Value[>..] = [];
    var scratch3: u8[>..] = [];
    let _, ok3 = cbor::decode_with(bytes3[..], opts2, values3, scratch3);
    assert(ok3);
}

fn test_tag_check() {
    var opts = cbor::DecodeOpts { max_depth: 64, reject_dups: false, check_tags: true };
    // Tag 4 with a byte string is a wrong shape.
    var bytes: u8[>..] = [];
    hex(bytes, "c44105");
    var values: cbor::Value[>..] = [];
    var scratch: u8[>..] = [];
    let _, ok = cbor::decode_with(bytes[..], opts, values, scratch);
    assert(!ok);
    // Tag 2 with a byte string is the right shape.
    var bytes2: u8[>..] = [];
    hex(bytes2, "c24105");
    var values2: cbor::Value[>..] = [];
    var scratch2: u8[>..] = [];
    let _, ok2 = cbor::decode_with(bytes2[..], opts, values2, scratch2);
    assert(ok2);
    // Tag 3 with a number is a wrong shape.
    var bytes3: u8[>..] = [];
    hex(bytes3, "c3010f");
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
    hex(text, "a24361626302617a01");
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
    hex(text2, "a2617a014361626302");
    assert(out == text2);
}

fn test_typed_lookups() {
    // A map with the keys 5, -6 and a byte string.
    var bytes: u8[>..] = [];
    hex(bytes, "a3050a25064361626307");
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
    hex(bytes, "c2420100");
    var values: cbor::Value[>..] = [];
    var scratch: u8[>..] = [];
    let tree, ok = cbor::decode(bytes[..], values, scratch);
    assert(ok);
    let n, nok = cbor::bignum_as_int(tree, tree.values[tree.root]);
    assert(nok);
    assert(n == 256);
    // A bignum of 2^63 does not fit an i64.
    var bytes2: u8[>..] = [];
    hex(bytes2, "c2488000000000000000");
    var values2: cbor::Value[>..] = [];
    var scratch2: u8[>..] = [];
    let tree2, ok2 = cbor::decode(bytes2[..], values2, scratch2);
    assert(ok2);
    let _, nok2 = cbor::bignum_as_int(tree2, tree2.values[tree2.root]);
    assert(!nok2);
    // The bigfloat writer and its reader.
    var out: u8[>..] = [];
    cbor::encode_bigfloat(out, 1, 2);
    expect_bytes(out, "c5820102");
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

fn test_canonical_check() {
    assert(cbor::is_canonical("\xf9\x3e\x00"));
    assert(!cbor::is_canonical("\xfb\x3f\xf8\x00\x00\x00\x00\x00\x00"));
    assert(cbor::is_canonical("\x01"));
    assert(!cbor::is_canonical("\x18\x01"));
    assert(!cbor::is_canonical("\x1a\x00\x00\x00\x01"));
}
    test_decode_first();
    test_depth_option();
    test_duplicate_keys();
    test_tag_check();
    test_rfc7049_sort();
    test_typed_lookups();
    test_tag_numbers();
    test_datetime_parse();
    test_canonical_check();
    test_cbor2_cases();
    print("all tests passed");
    return 0;
}

// The oracle cases of Python cbor2. Each case decodes, encodes again in
// the order of RFC 7049, and compares the bytes with the ones of cbor2.
fn test_cbor2_cases() {
    for c, i in cbor2_cases::CASE_INPUT {
        var bytes: u8[>..] = [];
        hex(bytes, c);
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
        hex(want, cbor2_cases::CASE_WANT[i]);
        if out != want {
            print("FAIL cbor2 case ", i, ": got ", out.len, " bytes, want ", want.len);
            assert(false);
        }
    }
}
