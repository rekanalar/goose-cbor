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
