#!/usr/bin/env python3
"""Write a blank 2DD D88 for user, data and save disks (games that ask for one in drive 1 or 2).

  tools/blank_d88.py OUT.d88 [--unformatted] [--fill BYTE]

Formatted (the default): 80 cylinders x 2 sides x 16 MFM sectors of 256 bytes, sector IDs C = cylinder, H = side,
R = 1-16, N = 1, data FFh (what the MZ's inverted bus reads as 00h). This is what most games take as a fresh
disk; some check for their own directory and offer to make a user disk from it. Unformatted: the D88 header only
(every track absent): for games that format the disk themselves (WRITE TRACK).
"""
import argparse, struct


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('out')
    ap.add_argument('--unformatted', action='store_true')
    ap.add_argument('--fill', type=lambda v: int(v, 0), default=0xFF)
    a = ap.parse_args()
    fill = a.fill
    tracks = []
    for t in range(0 if a.unformatted else 160):
        cyl, side = t >> 1, t & 1
        trk = bytearray()
        for r in range(1, 17):
            trk += struct.pack('<BBBBHBBB5xH', cyl, side, r, 1, 16, 0x00, 0, 0, 256) + bytes([fill]) * 256
        tracks.append(bytes(trk))
    hdr_len = 0x2B0
    offs, pos = [], hdr_len
    for trk in tracks:
        offs.append(pos)
        pos += len(trk)
    header = b'BLANK'.ljust(17, b'\0') + bytes(9) + bytes([0, 0x10]) + struct.pack('<I', pos)
    header += b''.join(struct.pack('<I', o) for o in (offs + [0] * 164)[:164])
    open(a.out, 'wb').write(header + b''.join(tracks))
    print('%s: %s, %d bytes' % (a.out, 'unformatted' if a.unformatted else '160 tracks x 16 x 256', pos))


if __name__ == '__main__':
    main()
