#!/usr/bin/env python3
"""Makes test/cbor_cases.goose for goose-cbor from cbor2.

Usage, in the package directory:
  PYTHONPATH=<dir with cbor2> python3 test/make_cbor_cases.py > test/cbor_cases.goose

Three kinds of case. A decode case holds bytes from cbor2 and the text that
the tree must render to. A refuse case holds a damaged document that cbor2
also refuses, or that cbor2 accepts. An encode case holds the bytes that
cbor2 writes for one value. The seed is fixed, so the output is stable.
The count goes to standard error.
"""
import io
import random
import struct
import sys

import cbor2

rng = random.Random(20261107)


def esc(b):
    return '"' + ''.join('\\x%02x' % c for c in b) + '"'


# render gives the text form that the Goose renderer must also give.
def render(v):
    if v is None:
        return 'N'
    if v is True:
        return 'T'
    if v is False:
        return 'F'
    if v is cbor2.undefined:
        return 'U'
    if isinstance(v, cbor2.CBORSimpleValue):
        return 's%d' % v.value
    if isinstance(v, int):
        if v >= 0:
            return 'u%d' % v
        return 'n%d' % (-1 - v)
    if isinstance(v, float):
        # A decoded NaN keeps no payload or sign, so every NaN renders alike.
        if v != v:
            return 'fnan'
        return 'f%016x' % struct.unpack('>Q', struct.pack('>d', v))[0]
    if isinstance(v, bytes):
        return 'b' + v.hex()
    if isinstance(v, str):
        return 't' + v.encode('utf-8').hex()
    if isinstance(v, list):
        return '[' + ','.join(render(x) for x in v) + ']'
    if isinstance(v, dict):
        return '{' + ','.join(render(k) + ':' + render(x) for k, x in v.items()) + '}'
    raise ValueError(v)


INTS = [0, 1, 23, 24, 25, 255, 256, 65535, 65536, 4294967295, 4294967296,
        2**63 - 1, 2**63, 2**64 - 1, -1, -24, -25, -256, -257, -65536, -65537,
        -4294967296, -4294967297, -2**63, -2**64]
FLOATS = [0.0, -0.0, 1.0, -1.0, 1.5, 0.1, 3.14159, 1e300, -1e300, 5e-324,
          1.1754943508222875e-38, 65504.0, 65536.0, 100000.0, 3.4028234663852886e38,
          float('inf'), float('-inf'), 2.0 ** -24, 2.0 ** -14, 1.0e-5]
TEXTS = ['', 'a', 'IETF', 'ü', '水', '\U00010151', 'a\u0000b', 'x' * 24, 'y' * 300, 'y' * 31, 'y' * 32,
         '\u007f', '\u0080', '߿', 'ࠀ', '￿', '\U0010ffff']
BYTES = [b'', b'\x00', b'\x01\x02\x03\x04', b'\xff' * 24, b'z' * 300, b'x' * 31, b'x' * 32, b'x' * 23]


def rand_scalar():
    k = rng.randrange(9)
    if k == 0:
        return rng.choice(INTS)
    if k == 1:
        return rng.randrange(-2**64, 2**64)
    if k == 2:
        return rng.choice(FLOATS)
    if k == 3:
        return rng.uniform(-1e6, 1e6)
    if k == 4:
        return rng.choice(TEXTS)
    if k == 5:
        return rng.choice(BYTES)
    if k == 6:
        return rng.choice([None, True, False, cbor2.undefined])
    if k == 7:
        return cbor2.CBORSimpleValue(rng.choice([0, 1, 19, 32, 100, 255]))
    return ''.join(chr(rng.choice([0x41, 0xe9, 0x6c34, 0x1f600])) for _ in range(rng.randrange(6)))


def rand_value(depth=0):
    if depth >= 3 or rng.random() < 0.55:
        return rand_scalar()
    if rng.random() < 0.5:
        return [rand_value(depth + 1) for _ in range(rng.randrange(5))]
    keys = ['a', 'b', 'c', 'dd', 'k%d' % rng.randrange(100), 'é']
    rng.shuffle(keys)
    return {k: rand_value(depth + 1) for k in keys[:rng.randrange(4)]}


def has_tag(b):
    """Says whether the walk of b meets a tag head (major type 6) before it ends or breaks.

    cbor2 checks the content of a tag when it decodes. This package checks it
    in the readers. So a damaged input that holds a tag is not a fair case.
    The walk only filters the generated inputs. It is not an oracle.
    """
    i, n = 0, len(b)
    stack = [1]
    while stack:
        if stack[-1] == 0:
            stack.pop()
            continue
        if i >= n:
            return False
        h = b[i]
        mt, info = h >> 5, h & 31
        if h == 0xff and stack[-1] == -1:
            stack.pop()
            i += 1
            continue
        if stack[-1] > 0:
            stack[-1] -= 1
        i += 1
        if mt == 6:
            return True
        if mt == 7:
            width = {24: 1, 25: 2, 26: 4, 27: 8}.get(info, 0)
            if info in (28, 29, 30, 31) or i + width > n:
                return False
            i += width
            continue
        if info == 31:
            if mt < 2:
                return False
            stack.append(-1)
            continue
        if info < 24:
            arg = info
        elif info <= 27:
            width = 1 << (info - 24)
            if i + width > n:
                return False
            arg = int.from_bytes(b[i:i + width], 'big')
            i += width
        else:
            return False
        if mt in (2, 3):
            if i + arg > n:
                return False
            i += arg
        elif mt == 4:
            stack.append(arg)
        elif mt == 5:
            stack.append(2 * arg)
    return False


def whole(b):
    """Gives cbor2's answer for b: (accepted, rendered). Trailing bytes count as a refusal."""
    s = io.BytesIO(b)
    try:
        v = cbor2.CBORDecoder(s).decode()
    except Exception:
        return False, None
    if s.tell() != len(b):
        return False, None
    try:
        return True, render(v)
    except ValueError:
        return True, None


lines = []
count = {'decode': 0, 'refuse': 0, 'accept': 0, 'enc_int': 0, 'enc_float': 0, 'enc_big': 0}

# Decode cases: values from the pools, each with its cbor2 bytes.
pool = [v for v in INTS] + FLOATS + TEXTS + BYTES
seen = set()
for v in pool:
    seen.add(cbor2.dumps(v))
while len(seen) < 260:
    seen.add(cbor2.dumps(rand_value()))
for b in sorted(seen):
    ok, text = whole(b)
    if not ok or text is None:
        continue
    lines.append('    expect_decode(%s, "%s");' % (esc(b), text))
    count['decode'] += 1

# Containers of length 31 and the lengths around it use the one-byte head.
for n in (30, 31, 32):
    for v in ([1] * n, {'k%02d' % i: i for i in range(n)}):
        b = cbor2.dumps(v)
        ok, text = whole(b)
        assert ok and text
        lines.append('    expect_decode(%s, "%s");' % (esc(b), text))
        count['decode'] += 1

# Float forms of 16 and 32 bits, which cbor2 reads and must render as doubles.
for h in ['f90000', 'f98000', 'f93c00', 'f97bff', 'f90001', 'f90400', 'f9c400', 'f97c00',
          'f9fc00', 'fa47c35000', 'fa00000001', 'fa7f800000', 'fa33800000',
          'fb7e37e43c8800759c', 'fb3ff199999999999a']:
    b = bytes.fromhex(h)
    ok, text = whole(b)
    assert ok and text, h
    lines.append('    expect_decode(%s, "%s");' % (esc(b), text))
    count['decode'] += 1

# Damaged documents. The truncation and the byte flip give no trailing bytes
# that cbor2 would skip, so cbor2 and the package must give the same answer.
good = sorted(seen)
mut = set()
tries = 0
while len(mut) < 340 and tries < 20000:
    tries += 1
    b = bytearray(rng.choice(good))
    if not b:
        continue
    kind = rng.randrange(4)
    if kind == 0:
        b = b[:rng.randrange(len(b))]
    elif kind == 1:
        b[rng.randrange(len(b))] = rng.randrange(256)
    elif kind == 2:
        b[0] = rng.randrange(256)
    else:
        i = rng.randrange(len(b))
        b[i] ^= 1 << rng.randrange(8)
    mut.add(bytes(b))
for b in sorted(mut):
    if has_tag(b):
        continue
    ok, text = whole(b)
    if ok and text is None:
        continue
    if ok:
        lines.append('    expect_accept(%s, "%s");' % (esc(b), text))
        count['accept'] += 1
    else:
        lines.append('    expect_refuse(%s);' % esc(b))
        count['refuse'] += 1

# Encoder cases.
enc = []
def enc_int(v):
    if v >= 0:
        return '    expect_enc_uint(%d, %s);' % (v, esc(cbor2.dumps(v)))
    return '    expect_enc_int(%d, %s);' % (v, esc(cbor2.dumps(v)))


for v in INTS:
    if -2**63 <= v < 2**64:
        enc.append(enc_int(v))
        count['enc_int'] += 1
for _ in range(60):
    v = rng.choice([rng.randrange(-2**63, 2**63), rng.randrange(0, 2**64), rng.randrange(0, 2**16), rng.randrange(-2**16, 0)])
    enc.append(enc_int(v))
    count['enc_int'] += 1


def goose_float(v):
    t = repr(v)
    if 'e' in t and '.' not in t:
        t = t.replace('e', '.0e')
    elif '.' not in t and 'e' not in t:
        t += '.0'
    return t


for v in FLOATS + [rng.uniform(-1e6, 1e6) for _ in range(30)] + [float(rng.randrange(-70000, 70000)) / 4 for _ in range(30)]:
    if v != v or v in (float('inf'), float('-inf')):
        continue
    enc.append('    expect_enc_float(%s, %s);' % (goose_float(v), esc(cbor2.dumps(v, canonical=True))))
    count['enc_float'] += 1
for _ in range(40):
    n = rng.randrange(1, 40)
    mag = bytes(rng.randrange(256) for _ in range(n))
    big = int.from_bytes(mag, 'big')
    for neg in (False, True):
        v = -1 - big if neg else big
        enc.append('    expect_enc_big(%s, %s, %s);' % ('true' if neg else 'false', esc(mag), esc(cbor2.dumps(v))))
        count['enc_big'] += 1

total = sum(count.values())
out = []
out.append('// Cases made by test/make_cbor_cases.py with cbor2 %s, seed 20261107.' % getattr(cbor2, '__version__', ''))
out.append('// Do not edit by hand. Make the file again with the script.')
out.append('// Count: %d cases (%s).' % (total, ', '.join('%s %d' % kv for kv in count.items())))
out.append('')
out.append(open(__file__.replace('make_cbor_cases.py', 'cbor_cases_head.txt')).read())
out.append('fn check_decode() {')
out.extend(lines)
out.append('}')
out.append('')
out.append('fn check_encode() {')
out.extend(enc)
out.append('}')
sys.stdout.write('\n'.join(out) + '\n')
sys.stderr.write('%d cases %s\n' % (total, count))
