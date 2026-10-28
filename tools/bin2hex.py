#!/usr/bin/env python3
"""Turn a raw binary into one little-endian 32-bit hex word per line, for $readmemh."""
import sys
data = open(sys.argv[1], 'rb').read()
data += b'\x00' * (-len(data) % 4)
with open(sys.argv[2], 'w') as f:
    for i in range(0, len(data), 4):
        f.write('%08x\n' % int.from_bytes(data[i:i+4], 'little'))
