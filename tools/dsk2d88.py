#!/usr/bin/env python3
"""Convert a CPC DSK floppy image (CPDRead, "MV - CPC" or "EXTENDED CPC DSK") to D88 (the core reads D88 only).

  tools/dsk2d88.py IN.dsk OUT.d88

As CSP's DISK::cpdread_to_d88 (disk.cpp, from MESS formats/dsk_dsk.c): each track's sector IDs (C H R N) and data are
copied in order; the FDC status bytes become the D88 sector status (ST2 bit 5, data CRC error: B0h; ST1 bit 5, ID CRC
error: A0h). DSK has no density, so every sector is MFM. The MZ-80B disks in the MAME list (CPDRead v3.24) have 16
sectors of 256 bytes per track plus a 17th sector marked as a data CRC error; it is kept, as CSP keeps it.

The bytes are copied as they are (D88 holds the media bytes; the MZ's inverted data bus is the controller's business).
The two MZ-80B disks have no IPL boot record: they are data disks for Disk BASIC SB-6510/6610, loaded from tape
(mz80b_cass); with the games disk in drive 1, SB-6510 starts its menu.
"""
import struct, sys


def main():
    src, dst = sys.argv[1], sys.argv[2]
    d = open(src, 'rb').read()
    ext = d.startswith(b'EXTENDED CPC DSK')
    if not ext and not d.startswith(b'MV - CPC'):
        sys.exit('not a CPC DSK image')
    ntrk, nside = d[0x30], d[0x31]
    if ext:
        sizes = [d[0x34 + i] * 256 for i in range(ntrk * nside)]
    else:
        sizes = [struct.unpack_from('<H', d, 0x32)[0]] * (ntrk * nside)
    tracks, p = [], 0x100
    for i, size in enumerate(sizes):
        if size == 0:
            tracks.append(b'')
            continue
        t = d[p:p + size]
        if not t.startswith(b'Track-Info') and t[1:10] != b'rack-Info':  # CPDRead leaves the first byte 0
            sys.exit('track %d: no Track-Info at %X' % (i, p))
        nsec, out, q = t[0x15], bytearray(), 0x100
        for k in range(nsec):
            c, h, r, n, st1, st2, ln = struct.unpack_from('<BBBBBBH', t, 0x18 + 8 * k)
            if not ext:
                ln = 128 << min(t[0x14], 6)
            data = t[q:q + ln]
            q += ln
            status = 0xB0 if st2 & 0x20 else 0xA0 if st1 & 0x20 else 0x10 if st2 & 0x40 else 0
            out += struct.pack('<BBBBHBBB5xH', c, h, r, n, nsec, 0x00, 0x10 if st2 & 0x40 else 0, status, len(data))
            out += data
        tracks.append(bytes(out))
        p += size
    hdr_len = 0x2B0
    offs, pos = [], hdr_len
    for t in tracks:
        offs.append(pos if t else 0)
        pos += len(t)
    name = src.rsplit('/', 1)[-1][:16].encode('ascii', 'replace')
    header = name.ljust(17, b'\0') + bytes(9) + bytes([0, 0x00]) + struct.pack('<I', pos)
    header += b''.join(struct.pack('<I', o) for o in (offs + [0] * 164)[:164])
    open(dst, 'wb').write(header + b''.join(tracks))
    print('%d tracks x %d sides, %d bytes' % (ntrk, nside, pos))


if __name__ == '__main__':
    main()
