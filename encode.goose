// The encoder for the cbor package. RFC 8949.
//
// Every writer appends into the buffer of the caller. The headers use
// the fewest bytes the value admits, so the output is the canonical
// form. The encoder writes definite lengths only.
namespace cbor;

import std;
import math;

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
        write_head(out, 1, ((-v) - 1) as u64);
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

// encode_float writes one f64. The encoder writes the full 8-byte form.
fn encode_float(out: u8[>..]&, v: f64) {
    out.push(0xfb);
    let bits = f64_to_bits(v);
    var shift = 56;
    while shift >= 0 {
        out.push((bits >> shift) as u8);
        shift -= 8;
    }
}

// f64_to_bits takes one f64 apart into its 64 bits. The math form:
// sign, biased exponent from log2, and the mantissa fraction.
fn f64_to_bits(v: f64) -> u64 {
    if v == 0.0 { return 0; }
    var sign: u64 = 0;
    var a = v;
    if v < 0.0 {
        sign = 9223372036854775808;
        a = -v;
    }
    if a != a { return sign | 9218868437227405312 | 1; }
    if a >= 1.7976931348623157e308 { return sign | 9218868437227405312; }
    let e: i64 = floor(log2(a)) as i64;
    let m = a / pow(2.0, e as f64);
    let frac: f64 = (m - 1.0) * 4503599627370496.0;
    let biased = e + 1023;
    if biased <= 0 {
        let sub = (frac * pow(2.0, biased as f64 - 52.0)) as u64;
        return sign | sub;
    }
    return sign | (biased as u64) << 52 | frac as u64;
}
