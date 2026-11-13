// The hex helpers of the cbor tests: read hex text into bytes and compare encodings.
namespace hex_helpers;

import std;
import cbor from "..";

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
