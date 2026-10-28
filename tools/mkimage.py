#!/usr/bin/env python3
"""Usage: mkimage.py boot.bin app.bin out.hex keyfile [--tamper]

Signs the application and builds the full ROM image. Header layout: magic, length, then
HMAC-SHA256(key, magic || length || payload). The bootloader is padded out to 0x1000 so the
app lands where the bootloader expects it. --tamper changes a payload byte after signing, to
mimic a modified image."""
import sys, struct, hmac, hashlib
boot = open(sys.argv[1], 'rb').read()
app = bytearray(open(sys.argv[2], 'rb').read())
key = bytes.fromhex(open(sys.argv[4]).read().strip())
assert len(boot) <= 0x1000, "bootloader exceeds 4 KB (%d)" % len(boot)
app += b'\x00' * (-len(app) % 4)
payload = bytes(app[40:])
struct.pack_into('<I', app, 4, len(payload))
mac = hmac.new(key, bytes(app[0:8]) + payload, hashlib.sha256).digest()
app[8:40] = mac
if '--tamper' in sys.argv:
    app[44] ^= 0xFF
img = boot + b'\x00' * (0x1000 - len(boot)) + bytes(app)
img += b'\x00' * (-len(img) % 4)
with open(sys.argv[3], 'w') as f:
    for i in range(0, len(img), 4):
        f.write('%08x\n' % int.from_bytes(img[i:i+4], 'little'))
print("boot %d B, app payload %d B, mac %s...%s" % (len(boot), len(payload), mac.hex()[:8],
      " (tampered)" if '--tamper' in sys.argv else ""))
