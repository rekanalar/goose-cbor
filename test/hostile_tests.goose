// The tests of hostile input: the audit probes, the length cases and the damaged documents.
namespace hostile_tests;

import std;
import cbor from "..";
import hex_helpers;

// probe decodes one hex input and checks the answer. The inputs are the
// 97 of the audit, with the answer of cbor2 and fxamacker/cbor. Six answers
// are the stated limits of this package: trailing bytes, the lazy tag
// checks and the depth limit.
fn probe(name: const u8[:], h: const u8[:], want_ok: bool) {
    var bytes: u8[>..] = [];
    hex_helpers::hex(bytes, h);
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
    hex_helpers::hex(b, "5bffffffffffffffff"); refuse_bytes(b[..]); b = [];
    hex_helpers::hex(b, "5b8000000000000000"); refuse_bytes(b[..]); b = [];
    hex_helpers::hex(b, "5b7fffffffffffffff"); refuse_bytes(b[..]); b = [];
    hex_helpers::hex(b, "7bffffffffffffffff"); refuse_bytes(b[..]); b = [];
    hex_helpers::hex(b, "7b7fffffffffffffff"); refuse_bytes(b[..]); b = [];
    hex_helpers::hex(b, "5a7fffffff"); refuse_bytes(b[..]); b = [];
    // A length that fits exactly passes. One byte more fails.
    hex_helpers::hex(b, "450102030405"); accept_bytes(b[..]); b = [];
    hex_helpers::hex(b, "46010203040506"); accept_bytes(b[..]); b = [];
    hex_helpers::hex(b, "4601020304"); refuse_bytes(b[..]); b = [];
    // A chunk of an indefinite string with a very large length.
    hex_helpers::hex(b, "5f5bffffffffffffffffff"); refuse_bytes(b[..]); b = [];
    hex_helpers::hex(b, "7f7b7fffffffffffffffff"); refuse_bytes(b[..]); b = [];

    // Array and map counts above the bytes left, and counts that look like the
    // sentinel value after a signed cast.
    hex_helpers::hex(b, "9bffffffffffffffff"); refuse_bytes(b[..]); b = [];
    hex_helpers::hex(b, "9b8000000000000000"); refuse_bytes(b[..]); b = [];
    hex_helpers::hex(b, "9b8000000000000000ff"); refuse_bytes(b[..]); b = [];
    hex_helpers::hex(b, "bbffffffffffffffff"); refuse_bytes(b[..]); b = [];
    hex_helpers::hex(b, "bb8000000000000000"); refuse_bytes(b[..]); b = [];
    hex_helpers::hex(b, "9affffffff"); refuse_bytes(b[..]); b = [];
    hex_helpers::hex(b, "9a000000050102"); refuse_bytes(b[..]); b = [];
    hex_helpers::hex(b, "a2616101"); refuse_bytes(b[..]); b = [];

    // 100000 levels of nesting fail at the depth limit.
    var deep: u8[>..] = [];
    for i in 0..100000 { deep.push(0x81); }
    deep.push(0x00);
    refuse_bytes(deep[..]);

    // One array of 100000 empty arrays, and one of 100000 integers.
    var wide: u8[>..] = [];
    hex_helpers::hex(wide, "9a000186a0");
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
    hex_helpers::hex(b, "581f");
    for i in 0..31 { b.push('x'); }
    accept_bytes(b[..]);
    var t: u8[>..] = [];
    hex_helpers::hex(t, "781f");
    for i in 0..31 { t.push('y'); }
    accept_bytes(t[..]);
    var a: u8[>..] = [];
    hex_helpers::hex(a, "981f");
    for i in 0..31 { a.push(0x01); }
    accept_bytes(a[..]);
    var m: u8[>..] = [];
    hex_helpers::hex(m, "b81f");
    for i in 0..31 { m.push(0x01); m.push(0x02); }
    accept_bytes(m[..]);
    // A chunk of 31 bytes in an indefinite string.
    var c: u8[>..] = [];
    hex_helpers::hex(c, "5f581f");
    for i in 0..31 { c.push('z'); }
    c.push(0xff);
    accept_bytes(c[..]);
    // One byte short is a fault.
    var s: u8[>..] = [];
    hex_helpers::hex(s, "581f");
    for i in 0..30 { s.push('x'); }
    refuse_bytes(s[..]);
}
