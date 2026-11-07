// The encoder for the cbor package. RFC 8949.
//
// Every writer appends into the buffer of the caller. The headers and
// the floats use the fewest bytes the value admits (RFC 8949 section
// 4.1). The encoder writes definite lengths only. A map is in the core
// deterministic form (section 4.2.1) after sort_map.
namespace cbor;

import std;
import math;
import value;
import decode;

// write_head writes one header: the major type and the value in the
// smallest form. The major type goes in the top three bits.
fn write_head(out: u8[>..]&, major: i32, val: u64) {
    let mt = (major as u8) << 5;
    if val < 24 {
        out.push(mt | (val as u8));
    } else if val <= 255 {
        out.push(mt | 24);
        out.push(val as u8);
    } else if val <= 65535 {
        out.push(mt | 25);
        out.push((val >> 8) as u8);
        out.push(val as u8);
    } else if val <= 4294967295 {
        out.push(mt | 26);
        out.push((val >> 24) as u8);
        out.push((val >> 16) as u8);
        out.push((val >> 8) as u8);
        out.push(val as u8);
    } else {
        out.push(mt | 27);
        var shift = 56;
        while shift >= 0 {
            out.push((val >> shift) as u8);
            shift -= 8;
        }
    }
}

// encode_uint writes one unsigned integer.
fn encode_uint(out: u8[>..]&, v: u64) {
    write_head(out, 0, v);
}

// encode_int writes one signed integer. The negatives use the magnitude
// form of RFC 8949: -n encodes as major 1 with the argument n-1.
fn encode_int(out: u8[>..]&, v: i64) {
    if v >= 0 {
        write_head(out, 0, v as u64);
    } else {
        write_head(out, 1, (-(v + 1)) as u64);
    }
}

// encode_bytes writes one byte string.
fn encode_bytes(out: u8[>..]&, b: const u8[:]) {
    write_head(out, 2, b.len as u64);
    out.append(b);
}

// encode_text writes one text string.
fn encode_text(out: u8[>..]&, t: const u8[:]) {
    write_head(out, 3, t.len as u64);
    out.append(t);
}

// encode_array_head writes the header of an array with n elements.
fn encode_array_head(out: u8[>..]&, n: u64) {
    write_head(out, 4, n);
}

// encode_map_head writes the header of a map with n pairs.
fn encode_map_head(out: u8[>..]&, n: u64) {
    write_head(out, 5, n);
}

// encode_tag writes the header of a tag with the number n. The tagged
// value follows.
fn encode_tag(out: u8[>..]&, n: u64) {
    write_head(out, 6, n);
}

// encode_bool writes true or false.
fn encode_bool(out: u8[>..]&, v: bool) {
    if v {
        out.push(0xf5);
    } else {
        out.push(0xf4);
    }
}

// encode_null writes null.
fn encode_null(out: u8[>..]&) {
    out.push(0xf6);
}

// Tag numbers of the standard tags (RFC 8949 section 3.4).
const TAG_DATETIME_STRING: u64 = 0;
const TAG_EPOCH: u64 = 1;
const TAG_BIGNUM_POS: u64 = 2;
const TAG_BIGNUM_NEG: u64 = 3;
const TAG_DECIMAL: u64 = 4;
const TAG_BIGFLOAT: u64 = 5;
const TAG_URI: u64 = 32;
const TAG_SELF_DESCRIBE: u64 = 55799;

// encode_datetime_string writes tag 0 and an RFC 3339 text. The caller
// supplies the text, for example "2013-03-21T20:04:00Z".
fn encode_datetime_string(out: u8[>..]&, t: const u8[:]) {
    write_head(out, 6, TAG_DATETIME_STRING);
    encode_text(out, t);
}

// encode_epoch writes tag 1 and whole seconds since 1970.
fn encode_epoch(out: u8[>..]&, secs: i64) {
    write_head(out, 6, TAG_EPOCH);
    encode_int(out, secs);
}

// encode_epoch_float writes tag 1 and fractional seconds. The float is
// the shortest form that keeps the value.
fn encode_epoch_float(out: u8[>..]&, secs: f64) {
    write_head(out, 6, TAG_EPOCH);
    encode_float(out, secs);
}

// encode_bignum writes the integer with the big-endian magnitude mag.
// For a negative integer n the magnitude is -1-n, as in RFC 8949. Leading
// zero bytes drop away. A magnitude of 8 bytes or less uses the plain
// integer form, which is the preferred serialization.
fn encode_bignum(out: u8[>..]&, negative: bool, mag: const u8[:]) {
    var at: i64 = 0;
    while at < mag.len && mag[at] == 0 { at += 1; }
    let m = mag[at..];
    if m.len <= 8 {
        var v: u64 = 0;
        for b in m { v = v << 8 | b; }
        write_head(out, if negative { 1 } else { 0 }, v);
        return;
    }
    write_head(out, 6, if negative { TAG_BIGNUM_NEG } else { TAG_BIGNUM_POS });
    encode_bytes(out, m);
}

// encode_decimal writes tag 4: the value is mantissa * 10^exponent.
fn encode_decimal(out: u8[>..]&, exponent: i64, mantissa: i64) {
    write_head(out, 6, TAG_DECIMAL);
    write_head(out, 4, 2);
    encode_int(out, exponent);
    encode_int(out, mantissa);
}

// less_bytes is the bytewise lexicographic order of RFC 8949 4.2.1.
fn less_bytes(a: const u8[:], b: const u8[:]) -> bool {
    var i: i64 = 0;
    while i < a.len && i < b.len {
        if a[i] != b[i] { return a[i] < b[i]; }
        i += 1;
    }
    return a.len < b.len;
}

// One key and value of a map, as offsets into the output buffer.
struct Pair { ks: i64, ke: i64, ve: i64 }

// sort_map puts the pairs of a map in the core deterministic order. Call
// encode_map_head(out, n), note start = out.len, write n key and value
// pairs, then call sort_map(out, start, n, tmp). The tmp buffer is
// scratch space. Nested maps must go through sort_map first. It gives
// false when the bytes after start are not n pairs.
fn sort_map(out: u8[>..]&, start: i64, n: i64, tmp: u8[>..]&) -> bool {
    var pairs: Pair[>..] = [];
    var pos = start;
    var i: i64 = 0;
    while i < n {
        let ke = item_end(out[..], pos);
        if ke < 0 { return false; }
        let ve = item_end(out[..], ke);
        if ve < 0 { return false; }
        pairs.push(Pair { ks: pos, ke: ke, ve: ve });
        pos = ve;
        i += 1;
    }
    if pos != out.len { return false; }
    tmp.append(out[start..]);
    let base = tmp.len - (out.len - start);
    sort(pairs[..]) { a, b => less_bytes(out[a.ks..a.ke], out[b.ks..b.ke]) };
    // Copy the sorted pairs from the old bytes: pairs index into out,
    // which still holds the old order, so take the bytes from tmp.
    var w = start;
    for p in pairs {
        var r = base + (p.ks - start);
        let end = base + (p.ve - start);
        while r < end {
            out[w] = tmp[r];
            w += 1;
            r += 1;
        }
    }
    return true;
}

// item_end gives the end offset of the data item that starts at pos, or
// -1 when the bytes do not hold a whole item.
fn item_end(s: const u8[:], pos: i64) -> i64 {
    var values: Value[>..] = [];
    var scratch: u8[>..] = [];
    var p = pos;
    let root, ok = decode_value(s, p, values, scratch);
    if !ok { return -1; }
    return p;
}

// encode_float writes one f64 in the shortest form that keeps the value
// (RFC 8949 section 4.1): 16, 32 or 64 bits. Every NaN is 0xf97e00, so
// the payload of a NaN is lost. The infinities are 0xf97c00 and 0xf9fc00.
fn encode_float(out: u8[>..]&, v: f64) {
    if v != v {
        out.push(0xf9);
        out.push(0x7e);
        out.push(0x00);
        return;
    }
    let neg = v < 0.0 || (v == 0.0 && 1.0 / v < 0.0);
    let a = if neg { -v } else { v };
    let sign: u64 = if neg { 1 } else { 0 };
    if a >= 1.0e308 * 10.0 {
        out.push(0xf9);
        out.push((sign << 7 | 0x7c) as u8);
        out.push(0x00);
        return;
    }
    if a == 0.0 || float_fits(a, -14, 15, 10) {
        let bits = sign << 15 | float_pack(a, -14, 10, 15);
        out.push(0xf9);
        out.push((bits >> 8) as u8);
        out.push(bits as u8);
    } else if float_fits(a, -126, 127, 23) {
        let bits = sign << 31 | float_pack(a, -126, 23, 127);
        out.push(0xfa);
        var shift = 24;
        while shift >= 0 {
            out.push((bits >> shift) as u8);
            shift -= 8;
        }
    } else {
        encode_float64_bits(out, sign, a);
    }
}

// encode_float64 writes one f64 in the full 8-byte form, whatever the
// value. Use it when a protocol wants no narrowing.
fn encode_float64(out: u8[>..]&, v: f64) {
    if v != v {
        out.push(0xfb);
        out.push(0x7f);
        var k = 0;
        out.push(0xf8);
        while k < 6 { out.push(0x00); k += 1; }
        return;
    }
    let neg = v < 0.0 || (v == 0.0 && 1.0 / v < 0.0);
    let a = if neg { -v } else { v };
    encode_float64_bits(out, if neg { 1 } else { 0 }, a);
}

fn encode_float64_bits(out: u8[>..]&, sign: u64, a: f64) {
    out.push(0xfb);
    var bits: u64 = sign << 63;
    if a >= 1.0e308 * 10.0 {
        bits = bits | 9218868437227405312;
    } else if a != 0.0 {
        bits = bits | float_pack(a, -1022, 52, 1023);
    }
    var shift = 56;
    while shift >= 0 {
        out.push((bits >> shift) as u8);
        shift -= 8;
    }
}

// float_exp gives e with 2^e <= a < 2^(e+1) for a finite a above zero.
fn float_exp(a: f64) -> i64 {
    var e: i64 = floor(log2(a)) as i64;
    // log2 can round across a power of two, so check both sides.
    if a >= pow(2.0, e as f64 + 1.0) { e += 1; }
    if a < pow(2.0, e as f64) { e -= 1; }
    return e;
}

// subnormal_scale gives a * 2^k in two steps, because 2^1074 alone
// overflows an f64.
fn subnormal_scale(a: f64, k: i64) -> f64 {
    return a * pow(2.0, (k / 2) as f64) * pow(2.0, (k - k / 2) as f64);
}

// float_fits tells whether a finite a above zero is exact in a binary
// format with the least normal exponent e_min, the greatest exponent
// e_max and mant fraction bits.
fn float_fits(a: f64, e_min: i64, e_max: i64, mant: i64) -> bool {
    let e = float_exp(a);
    if e > e_max { return false; }
    var x: f64 = 0.0;
    if e < e_min {
        x = subnormal_scale(a, mant - e_min);
        if x < 1.0 { return false; }
    } else {
        x = (a / pow(2.0, e as f64) - 1.0) * pow(2.0, mant as f64);
    }
    return x == floor(x);
}

// float_pack gives the exponent and fraction bits of a finite a above
// zero in the format of float_fits. The caller checked the fit.
fn float_pack(a: f64, e_min: i64, mant: i64, bias: i64) -> u64 {
    let e = float_exp(a);
    if e < e_min {
        return subnormal_scale(a, mant - e_min) as u64;
    }
    let frac = ((a / pow(2.0, e as f64) - 1.0) * pow(2.0, mant as f64)) as u64;
    return ((e + bias) as u64) << mant | frac;
}
