// The encoder for the cbor package. RFC 8949.
//
// Every writer appends into the buffer of the caller. The headers and
// the floats use the fewest bytes the value admits (RFC 8949 section
// 4.1). The encoder writes definite lengths only. A map is in the core
// deterministic form (section 4.2.1) after sort_map.
namespace cbor;

import std;
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

// f64_bits gives the IEEE 754 bit pattern of v as a u64. It reads the
// element bytes of an f64 array, so it runs no float arithmetic at all:
// the TinyCC JIT on macOS/arm64 mis-evaluates the log2, pow, floor and
// division-by-zero tricks that the old encoder used.
fn f64_bits(v: f64) -> u64 {
    let a: f64[1] = [v];
    let b = bytes_of(a);
    return b[0] | (b[1] as u64) << 8 | (b[2] as u64) << 16 | (b[3] as u64) << 24 |
        (b[4] as u64) << 32 | (b[5] as u64) << 40 | (b[6] as u64) << 48 | (b[7] as u64) << 56;
}

// narrow_bits tries to pack the finite positive double s * 2^(ue-52)
// (s holds the significand with the implicit bit) into a format with
// mant fraction bits, least normal exponent emin and exponent bias
// bias. It gives the packed exponent and fraction fields without the
// sign, and false when the value is not exact in the format.
fn narrow_bits(s: u64, ue: i64, mant: i64, emin: i64, bias: i64) -> u64, bool {
    if ue >= emin {
        // Normal target range: the format takes the top mant+1 bits
        // of the significand, so the rest must be zero.
        if ue > bias { return 0, false; }
        let drop = 52 - mant;
        if s & ((1 << drop) - 1) != 0 { return 0, false; }
        // The top bit of s is the implicit one; it does not go out.
        return ((ue + bias) as u64) << mant | s >> drop & ((1 << mant) - 1), true;
    }
    // Subnormal target range: the value must be a whole multiple of
    // the smallest subnormal of the format. A shift past 63 bits means
    // the value is far below it and never exact.
    let sh = 52 + emin - mant - ue;
    if sh > 63 { return 0, false; }
    if s & ((1 << sh) - 1) != 0 { return 0, false; }
    let f = s >> sh;
    if f == 0 || f >= (1 << mant) { return 0, false; }
    return f, true;
}

// encode_float writes one f64 in the shortest form that keeps the value
// (RFC 8949 section 4.1): 16, 32 or 64 bits. Every NaN is 0xf97e00, so
// the payload of a NaN is lost. The infinities are 0xf97c00 and 0xf9fc00.
// All decisions run on the integer bit pattern of v.
fn encode_float(out: u8[>..]&, v: f64) {
    let bits = f64_bits(v);
    let sign = bits >> 63;
    let exp = ((bits >> 52) & 2047) as i64;
    let frac = bits & 4503599627370495;
    if exp == 2047 {
        let h: u64 = if frac == 0 { sign << 15 | 0x7c00 } else { 0x7e00 };
        out.push(0xf9);
        out.push((h >> 8) as u8);
        out.push(h as u8);
        return;
    }
    if frac == 0 && exp == 0 {
        let h = sign << 15;
        out.push(0xf9);
        out.push((h >> 8) as u8);
        out.push(h as u8);
        return;
    }
    // s is the significand with the implicit bit; a double subnormal
    // has none. The value is s * 2^(ue-52).
    var s: u64 = frac;
    if exp != 0 { s = s | 4503599627370496; }
    let ue = exp - 1023;
    let h, hok = narrow_bits(s, ue, 10, -14, 15);
    if hok {
        let b = sign << 15 | h;
        out.push(0xf9);
        out.push((b >> 8) as u8);
        out.push(b as u8);
        return;
    }
    let w, sok = narrow_bits(s, ue, 23, -126, 127);
    if sok {
        let b = sign << 31 | w;
        out.push(0xfa);
        var shift = 24;
        while shift >= 0 {
            out.push((b >> shift) as u8);
            shift -= 8;
        }
        return;
    }
    out.push(0xfb);
    var shift = 56;
    while shift >= 0 {
        out.push((bits >> shift) as u8);
        shift -= 8;
    }
}

// encode_float64 writes one f64 in the full 8-byte form, whatever the
// value. Use it when a protocol wants no narrowing.
fn encode_float64(out: u8[>..]&, v: f64) {
    var bits = f64_bits(v);
    if bits >> 52 & 2047 == 2047 && bits & 4503599627370495 != 0 {
        bits = 0x7ff8000000000000;
    }
    out.push(0xfb);
    var shift = 56;
    while shift >= 0 {
        out.push((bits >> shift) as u8);
        shift -= 8;
    }
}
