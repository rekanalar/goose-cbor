// The decoder for the cbor package. RFC 8949.
//
// decode reads one value or a sequence of values into the arrays of the
// caller. The reader is a recursive-descent walk whose depth is the CBOR
// nesting depth, capped at 64; deeper input faults. Any input that ends
// inside a header or a payload faults, and so does every reserved
// additional-info form.
//
// The typed API reads one value of the asked kind from the front and
// gives the rest of the input back.
namespace cbor;

import std;
import math;
import value;

const MAX_DEPTH = 64;

// read_head gives the major type and the argument of the header at pos.
// The reader position moves past the header. A fault gives false.
fn read_head(s: const u8[:], pos: i64&, major: i32&, arg: u64&) -> bool {
    if pos >= s.len { return false; }
    let first = s[pos];
    pos += 1;
    major = first >> 5;
    let info = (first & 31) as i32;
    if info < 24 {
        arg = info as u64;
        return true;
    }
    if info == 24 {
        if pos >= s.len { return false; }
        arg = s[pos] as u64;
        pos += 1;
        return true;
    }
    if info == 25 {
        if pos + 1 >= s.len { return false; }
        arg = (s[pos] as u64) << 8 | s[pos + 1] as u64;
        pos += 2;
        return true;
    }
    if info == 26 {
        if pos + 3 >= s.len { return false; }
        arg = (s[pos] as u64) << 24 | (s[pos + 1] as u64) << 16
            | (s[pos + 2] as u64) << 8 | (s[pos + 3] as u64);
        pos += 4;
        return true;
    }
    if info == 27 {
        if pos + 7 >= s.len { return false; }
        var v: u64 = 0;
        var k = 0;
        while k < 8 {
            v = v << 8 | (s[pos + k] as u64);
            k += 1;
        }
        arg = v;
        pos += 8;
        return true;
    }
    // 28..31: reserved here; 31 is indefinite and the caller reads it
    // from the raw byte.
    return false;
}

// half_to_f64 expands one half-precision value in the 16 bits.
fn half_to_f64(h: u64) -> f64 {
    let sign = if (h >> 15) & 1 == 1 { -1.0 } else { 1.0 };
    let exp = ((h >> 10) & 31) as i64;
    let frac = (h & 1023) as f64;
    if exp == 0 {
        // Subnormal.
        return sign * frac * pow(2.0, -24.0);
    }
    if exp == 31 {
        if frac == 0.0 {
            // Infinity: a large product stands in for it.
            return sign * 1.0e308 * 10.0;
        }
        // NaN.
        return 0.0 / 0.0;
    }
    return sign * (1.0 + frac / 1024.0) * pow(2.0, exp - 15.0);
}

// single_to_f64 expands one single-precision value in the 32 bits.
fn single_to_f64(bits: u64) -> f64 {
    let sign = if (bits >> 31) & 1 == 1 { -1.0 } else { 1.0 };
    let exp = ((bits >> 23) & 255) as i64;
    let frac = (bits & 8388607) as f64;
    if exp == 0 { return sign * frac * pow(2.0, -149.0); }
    if exp == 255 {
        if frac == 0.0 { return sign * 1.0e308 * 10.0; }
        return 0.0 / 0.0;
    }
    return sign * (1.0 + frac / 8388608.0) * pow(2.0, exp - 127.0);
}

// bits_to_f64 rebuilds one f64 from its 64 bits.
fn bits_to_f64(bits: u64) -> f64 {
    let sign = if (bits >> 63) & 1 == 1 { -1.0 } else { 1.0 };
    let exp = ((bits >> 52) & 2047) as i64;
    let frac = (bits & 4503599627370495) as f64;
    if exp == 0 {
        if frac == 0.0 { return sign * 0.0; }
        return sign * frac * pow(2.0, -1074.0);
    }
    if exp == 2047 {
        if frac == 0.0 {
            return sign * 1.0e308 * 10.0;
        }
        return 0.0 / 0.0;
    }
    return sign * (1.0 + frac / 4503599627370496.0) * pow(2.0, exp - 1023.0);
}

// One work item of the explicit stack: a container that still needs
// children. remaining holds the count of children to read, or -1 for an
// indefinite container.
struct Work {
    parent: i32,
    remaining: i64,
}

// read_one reads one value at pos and pushes the node. It gives the
// node index, the child count (with maps doubled), or -1 when the
// value needs no children, and the indefinite flag. A fault gives a
// negative node index.
fn read_one(s: const u8[:], pos: i64, values: Value[>..]&, scratch: u8[>..]&) -> i32, i64, i64, bool, bool {
    var remaining: i64 = -1;
    var indefinite = false;
    var pos = pos;
    if pos >= s.len { return -1, pos, remaining, indefinite, false; }
    let first = s[pos];
    let info = (first & 31) as i32;
    let major = first >> 5;
    if major == 7 && info == 31 { return -1, pos, remaining, indefinite, false; }
    var mt: i32 = 0;
    var arg: u64 = 0;
    if !read_head(s, pos, mt, arg) {
        if info == 31 {
            arg = 31;
            mt = major;
        } else {
            return -1, pos, remaining, indefinite, false;
        }
    }
    indefinite = false;
    remaining = -1;
    if mt == 0 {
        values.push(Value { kind: K_UINT, uint: arg, float: 0.0, span: s[0..0], first_child: -1, next_sibling: -1 });
        return values.len as i32 - 1, pos, remaining, indefinite, true;
    }
    if mt == 1 {
        values.push(Value { kind: K_NEG, uint: arg, float: 0.0, span: s[0..0], first_child: -1, next_sibling: -1 });
        return values.len as i32 - 1, pos, remaining, indefinite, true;
    }
    if mt == 2 || mt == 3 {
        let kind: i32 = if mt == 2 { K_BYTES } else { K_TEXT };
        if arg != 31 {
            let n = arg as i64;
            if pos + n > s.len { return -1, pos, remaining, indefinite, false; }
            values.push(Value { kind: kind, uint: 0, float: 0.0, span: s[pos..pos + n], first_child: -1, next_sibling: -1 });
            pos += n;
            return values.len as i32 - 1, pos, remaining, indefinite, true;
        }
        // Indefinite: chunks until the break byte.
        let joined_at = scratch.len;
        while true {
            if pos >= s.len { return -1, pos, remaining, indefinite, false; }
            if s[pos] == 0xff {
                pos += 1;
                break;
            }
            var cmt: i32 = 0;
            var carg: u64 = 0;
            if !read_head(s, pos, cmt, carg) {
                if (s[pos] & 31) == 31 {
                    cmt = s[pos] >> 5;
                    carg = 31;
                } else {
                    return -1, pos, remaining, indefinite, false;
                }
            }
            if cmt != mt || carg == 31 { return -1, pos, remaining, indefinite, false; }
            let n = carg as i64;
            if pos + n > s.len { return -1, pos, remaining, indefinite, false; }
            scratch.append(s[pos..pos + n]);
            pos += n;
        }
        values.push(Value { kind: kind, uint: 0, float: 0.0, span: scratch[joined_at..scratch.len], first_child: -1, next_sibling: -1 });
        return values.len as i32 - 1, pos, remaining, indefinite, true;
    }
    if mt == 4 || mt == 5 {
        let kind: i32 = if mt == 4 { K_ARRAY } else { K_MAP };
        if arg != 31 {
            remaining = arg as i64;
            if mt == 5 { remaining *= 2; }
        } else {
            indefinite = true;
            remaining = -1;
        }
        values.push(Value { kind: kind, uint: 0, float: 0.0, span: s[0..0], first_child: -1, next_sibling: -1 });
        return values.len as i32 - 1, pos, remaining, indefinite, true;
    }
    if mt == 6 {
        values.push(Value { kind: K_TAG, uint: arg, float: 0.0, span: s[0..0], first_child: -1, next_sibling: -1 });
        remaining = 1;
        return values.len as i32 - 1, pos, remaining, indefinite, true;
    }
    // Major 7.
    if info == 20 {
        values.push(Value { kind: K_BOOL, uint: 0, float: 0.0, span: s[0..0], first_child: -1, next_sibling: -1 });
        return values.len as i32 - 1, pos, remaining, indefinite, true;
    }
    if info == 21 {
        values.push(Value { kind: K_BOOL, uint: 1, float: 0.0, span: s[0..0], first_child: -1, next_sibling: -1 });
        return values.len as i32 - 1, pos, remaining, indefinite, true;
    }
    if info == 22 {
        values.push(Value { kind: K_NULL, uint: 0, float: 0.0, span: s[0..0], first_child: -1, next_sibling: -1 });
        return values.len as i32 - 1, pos, remaining, indefinite, true;
    }
    if info == 23 { return -1, pos, remaining, indefinite, false; }
    if info == 25 {
        values.push(Value { kind: K_FLOAT, uint: 0, float: half_to_f64(arg), span: s[0..0], first_child: -1, next_sibling: -1 });
        return values.len as i32 - 1, pos, remaining, indefinite, true;
    }
    if info == 26 || info == 27 {
        let fv = if info == 26 { single_to_f64(arg) } else { bits_to_f64(arg) };
        values.push(Value { kind: K_FLOAT, uint: 0, float: fv, span: s[0..0], first_child: -1, next_sibling: -1 });
        return values.len as i32 - 1, pos, remaining, indefinite, true;
    }
    // A simple value the package does not know.
    return -1, pos, remaining, indefinite, false;
}

// decode_value reads one value at pos into the arrays. The walk uses an
// explicit stack, so no recursion runs. The stack depth is capped at
// 64. The scratch buffer holds the joined bytes of indefinite strings.
fn decode_value(s: const u8[:], pos: i64&, values: Value[>..]&, scratch: u8[>..]&) -> i32, bool {
    var stack: Work[>..] = [];
    var remaining: i64 = -1;
    var indefinite = false;

    var root_remaining: i64 = -1;
    var root_indef = false;
    let root, npos, root_remaining, root_indef, ok = read_one(s, pos, values, scratch);
    if !ok { return -1, false; }
    pos = npos;
    if root_remaining != -1 || root_indef {
        if stack.len >= MAX_DEPTH { return -1, false; }
        stack.push(Work { parent: root, remaining: root_remaining });
    }

    // The work loop: fill the containers on the stack.
    while stack.len > 0 {
        let top = stack[stack.len - 1];
        if top.remaining == 0 {
            stack.pop();
            continue;
        }
        if top.remaining < 0 {
            // Indefinite: the break byte ends the container.
            if pos >= s.len { return -1, false; }
            if s[pos] == 0xff {
                pos += 1;
                stack.pop();
                continue;
            }
        }
        let child, npos2, c_remaining, c_indef, cok = read_one(s, pos, values, scratch);
        if !cok { return -1, false; }
        pos = npos2;
        // Link the child as the last child of the parent.
        let p = top.parent;
        if values[p].first_child < 0 {
            values[p].first_child = child;
        } else {
            var last = values[p].first_child;
            while values[last].next_sibling >= 0 {
                last = values[last].next_sibling;
            }
            values[last].next_sibling = child;
        }
        if top.remaining > 0 {
            stack[stack.len - 1].remaining -= 1;
        }
        if c_remaining != -1 || c_indef {
            if stack.len >= MAX_DEPTH { return -1, false; }
            stack.push(Work { parent: child, remaining: c_remaining });
        }
    }
    return root, true;
}

// decode reads one value into the arrays of the caller. The arrays and
// the scratch buffer come from the caller and must outlive the Tree. On
// success the root index holds the value.
fn decode(s: const u8[:], values: Value[>..]&, scratch: u8[>..]&) -> Tree, bool {
    var pos: i64 = 0;
    let root, ok = decode_value(s, pos, values, scratch);
    if !ok { return Tree { values: values[..], root: -1 }, false; }
    // Trailing bytes are a fault for a single document.
    if pos != s.len { return Tree { values: values[..], root: -1 }, false; }
    return Tree { values: values[..], root: root }, true;
}

// The typed API. Each read takes one value of the asked kind from the
// front and gives the rest of the input back.

fn read_uint(s: const u8[:]) -> u64, const u8[:], bool {
    var pos: i64 = 0;
    var mt: i32 = 0;
    var arg: u64 = 0;
    if !read_head(s, pos, mt, arg) { return 0, s[0..0], false; }
    if mt != 0 { return 0, s[0..0], false; }
    return arg, s[pos..], true;
}

fn read_int(s: const u8[:]) -> i64, const u8[:], bool {
    var pos: i64 = 0;
    var mt: i32 = 0;
    var arg: u64 = 0;
    if !read_head(s, pos, mt, arg) { return 0, s[0..0], false; }
    if mt == 0 {
        if arg > 9223372036854775807 { return 0, s[0..0], false; }
        return arg as i64, s[pos..], true;
    }
    if mt == 1 {
        if arg > 9223372036854775807 { return 0, s[0..0], false; }
        let m = arg as i64;
        return -m - 1, s[pos..], true;
    }
    return 0, s[0..0], false;
}

fn read_text(s: const u8[:]) -> const u8[:], const u8[:], bool {
    var pos: i64 = 0;
    var mt: i32 = 0;
    var arg: u64 = 0;
    if !read_head(s, pos, mt, arg) { return "", s[0..0], false; }
    if mt != 3 || arg == 31 { return "", s[0..0], false; }
    let n = arg as i64;
    if pos + n > s.len { return "", s[0..0], false; }
    return s[pos..pos + n], s[pos + n..], true;
}

fn read_bytes(s: const u8[:]) -> const u8[:], const u8[:], bool {
    var pos: i64 = 0;
    var mt: i32 = 0;
    var arg: u64 = 0;
    if !read_head(s, pos, mt, arg) { return "", s[0..0], false; }
    if mt != 2 || arg == 31 { return "", s[0..0], false; }
    let n = arg as i64;
    if pos + n > s.len { return "", s[0..0], false; }
    return s[pos..pos + n], s[pos + n..], true;
}

fn read_float(s: const u8[:]) -> f64, const u8[:], bool {
    var pos: i64 = 0;
    var mt: i32 = 0;
    var arg: u64 = 0;
    if pos >= s.len { return 0.0, s[0..0], false; }
    let info = (s[pos] & 31) as i32;
    if !read_head(s, pos, mt, arg) { return 0.0, s[0..0], false; }
    if mt != 7 { return 0.0, s[0..0], false; }
    if info == 25 { return half_to_f64(arg), s[pos..], true; }
    if info == 26 { return single_to_f64(arg), s[pos..], true; }
    if info == 27 { return bits_to_f64(arg), s[pos..], true; }
    return 0.0, s[0..0], false;
}

fn read_bool(s: const u8[:]) -> bool, const u8[:], bool {
    if s.len == 0 { return false, s[0..0], false; }
    if s[0] == 0xf4 { return false, s[1..], true; }
    if s[0] == 0xf5 { return true, s[1..], true; }
    return false, s[0..0], false;
}

fn read_null(s: const u8[:]) -> const u8[:], bool {
    if s.len == 0 { return s[0..0], false; }
    if s[0] == 0xf6 { return s[1..], true; }
    return s[0..0], false;
}
