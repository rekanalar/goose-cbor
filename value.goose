// The value tree for the cbor package.
//
// A decoded document is one grow-only array of Value. The children link
// through first_child and next_sibling, so an array walks its elements
// and a map walks key, value, key, value. Text and byte payloads are
// spans over the input, so the input must outlive the array.
namespace cbor;

import std;

const K_UINT = 0;
const K_NEG = 1;
const K_BYTES = 2;
const K_TEXT = 3;
const K_ARRAY = 4;
const K_MAP = 5;
const K_TAG = 6;
const K_BOOL = 7;
const K_NULL = 8;
const K_FLOAT = 9;
const K_UNDEFINED = 10;
const K_SIMPLE = 11;

// Value holds one decoded value.
struct Value {
    kind: i32,
    uint: u64,
    float: f64,
    span: const u8[:],
    first_child: i32,
    next_sibling: i32,
}

// Tree holds the decoded values and the root index. The arrays come
// from the caller, so they outlive the Tree.
struct Tree {
    values: Value[],
    root: i32,
}

// as_uint gives the unsigned value of a uint node. Another kind gives
// false.
fn as_uint(v: Value&) -> u64, bool {
    if v.kind != K_UINT { return 0, false; }
    return v.uint, true;
}

// as_int gives the signed value of a uint or a negative node. A value
// beyond i64 gives false.
fn as_int(v: Value&) -> i64, bool {
    if v.kind == K_UINT {
        if v.uint > 9223372036854775807 { return 0, false; }
        return v.uint as i64, true;
    }
    if v.kind == K_NEG {
        if v.uint > 9223372036854775807 { return 0, false; }
        let m = v.uint as i64;
        return -m - 1, true;
    }
    return 0, false;
}

// as_text gives the text span of a text node. Another kind gives false.
fn as_text(v: Value&) -> const u8[:], bool {
    if v.kind != K_TEXT { return "", false; }
    return v.span, true;
}

// as_bytes gives the byte span of a bytes node. Another kind gives
// false.
fn as_bytes(v: Value&) -> const u8[:], bool {
    if v.kind != K_BYTES { return "", false; }
    return v.span, true;
}

// as_float gives the float value of a float node. Another kind gives
// false.
fn as_float(v: Value&) -> f64, bool {
    if v.kind != K_FLOAT { return 0.0, false; }
    return v.float, true;
}

// as_bool gives the bool value of a bool node. Another kind gives false.
fn as_bool(v: Value&) -> bool, bool {
    if v.kind != K_BOOL { return false, false; }
    return v.uint != 0, true;
}

// child_at gives the child at the place at of an array or a tag. A
// place outside or another kind gives false.
fn child_at(t: Tree&, v: Value&, at: i64) -> Value&, bool {
    if v.kind != K_ARRAY && v.kind != K_TAG { return t.values[0], false; }
    if v.kind == K_TAG && at != 0 { return t.values[0], false; }
    var id = v.first_child;
    var i: i64 = 0;
    while id >= 0 {
        if i == at { return t.values[id], true; }
        id = t.values[id].next_sibling;
        i += 1;
    }
    return t.values[0], false;
}

// array_len gives the element count of an array node.
fn array_len(t: Tree&, v: Value&) -> i64 {
    if v.kind != K_ARRAY { return 0; }
    var id = v.first_child;
    var n: i64 = 0;
    while id >= 0 {
        id = t.values[id].next_sibling;
        n += 1;
    }
    return n;
}

// map_get gives the value of the key that matches at the top level of
// the map. The keys compare as raw bytes. An absent key gives false.
fn map_get(t: Tree&, v: Value&, key: const u8[:]) -> Value&, bool {
    if v.kind != K_MAP { return t.values[0], false; }
    var id = v.first_child;
    while id >= 0 {
        let k = t.values[id];
        if k.kind == K_TEXT && k.span == key {
            let vid = k.next_sibling;
            if vid >= 0 { return t.values[vid], true; }
            return t.values[0], false;
        }
        id = k.next_sibling;
        if id >= 0 { id = t.values[id].next_sibling; }
    }
    return t.values[0], false;
}

// as_tag gives the tag number of a tag node. Another kind gives false.
fn as_tag(v: Value&) -> u64, bool {
    if v.kind != K_TAG { return 0, false; }
    return v.uint, true;
}

// as_datetime_string gives the text of a tag 0 node. A tag with another
// number, or content that is not text, gives false.
fn as_datetime_string(t: Tree&, v: Value&) -> const u8[:], bool {
    if v.kind != K_TAG || v.uint != 0 { return "", false; }
    let c, ok .= child_at(t, v, 0);
    if !ok { return "", false; }
    return as_text(c);
}

// as_epoch gives the seconds since 1970 of a tag 1 node, as a float.
// The content is an integer or a float.
fn as_epoch(t: Tree&, v: Value&) -> f64, bool {
    if v.kind != K_TAG || v.uint != 1 { return 0.0, false; }
    let c, ok .= child_at(t, v, 0);
    if !ok { return 0.0, false; }
    let f, isf = as_float(c);
    if isf { return f, true; }
    let i, isi = as_int(c);
    if isi { return i as f64, true; }
    return 0.0, false;
}

// as_bignum reads a tag 2 or tag 3 node. It gives the negative flag and
// the big-endian magnitude. For a negative node the integer is -1-mag.
fn as_bignum(t: Tree&, v: Value&) -> bool, const u8[:], bool {
    if v.kind != K_TAG || (v.uint != 2 && v.uint != 3) { return false, "", false; }
    let c, ok .= child_at(t, v, 0);
    if !ok { return false, "", false; }
    let b, isb = as_bytes(c);
    if !isb { return false, "", false; }
    return v.uint == 3, b, true;
}

// as_undefined says whether the node is the undefined value (byte f7).
fn as_undefined(v: Value&) -> bool {
    return v.kind == K_UNDEFINED;
}

// as_simple gives the number of a simple value node. The numbers are 0 to
// 19 and 32 to 255. Another kind gives false.
fn as_simple(v: Value&) -> u64, bool {
    if v.kind != K_SIMPLE { return 0, false; }
    return v.uint, true;
}

// map_find walks the map node v and gives the value of the key that
// matches the kind and the payload. The number holds the key for a uint
// node and the key for a neg node. The bytes hold the key for a bytes
// node.
fn map_find(t: Tree&, v: Value&, kind: i32, number: u64, bytes: const u8[:]) -> Value&, bool {
    if v.kind != K_MAP { return t.values[0], false; }
    var id = v.first_child;
    while id >= 0 {
        let key = t.values[id];
        var hit = false;
        if key.kind == kind {
            if kind == K_BYTES || kind == K_TEXT {
                hit = key.span == bytes;
            } else if kind == K_NEG {
                // A neg node holds -1-k, which is the bitwise complement of k.
                hit = key.uint == ~number;
            } else {
                hit = key.uint == number;
            }
        }
        if hit {
            let vid = key.next_sibling;
            if vid >= 0 { return t.values[vid], true; }
            return t.values[0], false;
        }
        id = key.next_sibling;
        if id >= 0 { id = t.values[id].next_sibling; }
    }
    return t.values[0], false;
}

// map_get_uint looks the uint key k up in the map node v. A found result
// holds the value child of the pair.
fn map_get_uint(t: Tree&, v: Value&, k: u64) -> Value&, bool {
    return map_find(t, v, K_UINT, k, "");
}

// map_get_int looks the negative integer key k up.
fn map_get_int(t: Tree&, v: Value&, k: i64) -> Value&, bool {
    return map_find(t, v, K_NEG, k as u64, "");
}

// map_get_bytes looks the byte-string key up.
fn map_get_bytes(t: Tree&, v: Value&, key: const u8[:]) -> Value&, bool {
    return map_find(t, v, K_BYTES, 0, key);
}

// bignum_as_int gives the value of a tag 2 or tag 3 node as an i64. The
// magnitude must hold in 8 bytes and stay inside the range of i64. A
// wider bignum gives false.
fn bignum_as_int(t: Tree&, v: Value&) -> i64, bool {
    let neg, mag, ok = as_bignum(t, v);
    if !ok { return 0, false; }
    if mag.len > 8 { return 0, false; }
    var m: u64 = 0;
    for b in mag {
        m = m << 8 | b;
    }
    if neg {
        // The value is -1-mag. mag = 2^63 would give one below the
        // smallest i64, so the range check keeps a guard bit.
        if m > 9223372036854775807 { return 0, false; }
        return -1 - (m as i64), true;
    }
    if m > 9223372036854775807 { return 0, false; }
    return m as i64, true;
}

// as_bigfloat gives the exponent and the mantissa of a tag 5 node. The
// value is mantissa * 2^exponent. A whole float content converts; a
// fractional one gives false.
fn as_bigfloat(t: Tree&, v: Value&) -> i64, i64, bool {
    if v.kind != K_TAG || v.uint != 5 { return 0, 0, false; }
    let c, ok .= child_at(t, v, 0);
    if !ok { return 0, 0, false; }
    let e, eok .= child_at(t, c, 0);
    let m, mok .= child_at(t, c, 1);
    if !eok || !mok { return 0, 0, false; }
    let ei, iok = as_int(e);
    if !iok {
        let ef, fok = as_float(e);
        if !fok || !whole(ef) { return 0, 0, false; }
        let mi, mok2 = int_part(m);
        if !mok2 { return 0, 0, false; }
        return ef as i64, mi, true;
    }
    let mi, mok2 = int_part(m);
    if !mok2 { return 0, 0, false; }
    return ei, mi, true;
}

// whole tells whether the float holds a whole number inside the range
// of i64. The check avoids the trunc of the math module.
fn whole(f: f64) -> bool {
    if f != f { return false; }
    if f < -9223372036854775808.0 || f >= 9223372036854775808.0 { return false; }
    let i = f as i64;
    return f == i as f64;
}

// int_part reads one number node as an i64. An integral float converts.
fn int_part(v: Value&) -> i64, bool {
    let i, iok = as_int(v);
    if iok { return i, true; }
    let f, fok = as_float(v);
    if fok && whole(f) { return f as i64, true; }
    return 0, false;
}

// datetime_to_epoch parses the RFC 3339 text of a tag 0 into the seconds
// since 1970. It takes T or a space between the date and the time, an
// optional fraction, and the offsets Z, +hh:mm and -hh:mm.
fn datetime_to_epoch(text: const u8[:]) -> f64, bool {
    if text.len < 20 { return 0.0, false; }
    let d = digits4(text, 0);
    if d < 0 { return 0.0, false; }
    if text[4] != '-' || text[7] != '-' { return 0.0, false; }
    let mo = digits2(text, 5);
    if mo < 1 || mo > 12 { return 0.0, false; }
    let da = digits2(text, 8);
    if da < 1 || da > 31 { return 0.0, false; }
    if text[10] != 'T' && text[10] != 't' && text[10] != ' ' { return 0.0, false; }
    let hh = digits2(text, 11);
    if hh < 0 || hh > 23 { return 0.0, false; }
    if text[13] != ':' { return 0.0, false; }
    let mi = digits2(text, 14);
    if mi < 0 || mi > 59 { return 0.0, false; }
    if text[16] != ':' { return 0.0, false; }
    let ss = digits2(text, 17);
    if ss < 0 || ss > 60 { return 0.0, false; }
    var i: i64 = 19;
    var frac: f64 = 0.0;
    if text.len > i && text[i] == '.' {
        i += 1;
        var scale: f64 = 0.1;
        var got = false;
        while i < text.len && text[i] >= '0' && text[i] <= '9' {
            frac += (text[i] - '0') * scale;
            scale /= 10.0;
            i += 1;
            got = true;
        }
        if !got { return 0.0, false; }
    }
    var offset: i64 = 0;
    if i >= text.len { return 0.0, false; }
    if text[i] == 'Z' || text[i] == 'z' {
        if i + 1 != text.len { return 0.0, false; }
    } else if text[i] == '+' || text[i] == '-' {
        let sign: i64 = if text[i] == '-' { -1 } else { 1 };
        if text.len != i + 6 { return 0.0, false; }
        if text[i + 3] != ':' { return 0.0, false; }
        let oh = digits2(text, i + 1);
        let om = digits2(text, i + 4);
        if oh < 0 || oh > 23 || om < 0 || om > 59 { return 0.0, false; }
        offset = sign * (oh * 3600 + om * 60);
    } else {
        return 0.0, false;
    }
    let days = days_from_civil(d, mo, da);
    let secs = days * 86400 + hh * 3600 + mi * 60 + ss - offset;
    return secs + frac, true;
}

// digits4 gives the two-digit or four-digit number at pos. A digit that
// is not ASCII gives -1.
fn digits2(s: const u8[:], pos: i64) -> i64 {
    if pos + 1 >= s.len { return -1; }
    if s[pos] < '0' || s[pos] > '9' { return -1; }
    if s[pos + 1] < '0' || s[pos + 1] > '9' { return -1; }
    return (s[pos] - '0') * 10 + (s[pos + 1] - '0');
}

fn digits4(s: const u8[:], pos: i64) -> i64 {
    if pos + 3 >= s.len { return -1; }
    var y: i64 = 0;
    var k: i64 = 0;
    while k < 4 {
        if s[pos + k] < '0' || s[pos + k] > '9' { return -1; }
        y = y * 10 + (s[pos + k] - '0');
        k += 1;
    }
    return y;
}

// days_from_civil gives the day count of the proleptic Gregorian date,
// with 1970-01-01 as day 0. The algorithm is the one of Howard Hinnant.
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let yy = if m <= 2 { y - 1 } else { y };
    var base: i64 = yy;
    if yy < 0 { base = yy - 399; }
    let era = base / 400;
    let yoe = yy - era * 400;
    let mp = if m > 2 { m - 3 } else { m + 9 };
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}
