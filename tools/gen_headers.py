#!/usr/bin/env python3
"""Usage: gen_headers.py <keyfile> <outdir>

Writes sha_consts.h (the SHA-256 round constants, computed from the first primes rather than
pasted in) and key.h (the HMAC key from the key file) for the bootloader to include."""
import sys, os
def isqrt(n):
    x = 1 << ((n.bit_length() + 1) // 2)
    while True:
        y = (x + n // x) // 2
        if y >= x: return x
        x = y
def icbrt(n):
    x = 1 << ((n.bit_length() + 2) // 3 + 1)
    while True:
        y = (2 * x + n // (x * x)) // 3
        if y >= x: return x
        x = y
primes, c = [], 2
while len(primes) < 64:
    if all(c % p for p in primes if p * p <= c): primes.append(c)
    c += 1
K  = [icbrt(p << 96) & 0xFFFFFFFF for p in primes]
H0 = [isqrt(p << 64) & 0xFFFFFFFF for p in primes[:8]]
key = bytes.fromhex(open(sys.argv[1]).read().strip()); assert len(key) == 32
out = sys.argv[2]; os.makedirs(out, exist_ok=True)
with open(os.path.join(out, 'sha_consts.h'), 'w') as f:
    f.write('static const uint32_t SHA_K[64] = {' + ','.join('0x%08xu' % k for k in K) + '};\n')
    f.write('static const uint32_t SHA_H0[8] = {' + ','.join('0x%08xu' % h for h in H0) + '};\n')
with open(os.path.join(out, 'key.h'), 'w') as f:
    f.write('static const uint8_t HMAC_KEY[32] = {' + ','.join('0x%02x' % b for b in key) + '};\n')
