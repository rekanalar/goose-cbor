// The tests of the float forms: shortest encoding, edge values and single floats.
namespace float_tests;

import std;
import cbor from "..";
import hex_helpers;

// float_case encodes v in the shortest form, checks the RFC bytes, then
// decodes them and checks the value comes back.
fn float_case(v: f64, want_hex: const u8[:]) {
    var out: u8[>..] = [];
    cbor::encode_float(out, v);
    hex_helpers::expect_bytes(out, want_hex);
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
    hex_helpers::expect_bytes(out, "fb3ff0000000000000");
    out = [];
    cbor::encode_float64(out, nan_value());
    hex_helpers::expect_bytes(out, "fb7ff8000000000000");
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
    let t, ok = hex_helpers::decode_hex("fa47c35000", b, v, s);
    assert(ok);
    let f, g = cbor::as_float(t.values[t.root]);
    assert(g && f == 100000.0);
    var v2: cbor::Value[>..] = [];
    var s2: u8[>..] = [];
    var b2: u8[>..] = [];
    let t2, ok2 = hex_helpers::decode_hex("fa7f7fffff", b2, v2, s2);
    assert(ok2);
    let f2, g2 = cbor::as_float(t2.values[t2.root]);
    assert(g2 && f2 == 3.4028234663852886e+38);
}
