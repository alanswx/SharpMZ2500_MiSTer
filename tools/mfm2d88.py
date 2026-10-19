#!/usr/bin/env python3
"""Decode a MAME floppy image (MFI, flux level) or an HxC MFM bitstream image (HXCMFM) to D88.

  tools/mfm2d88.py IN.mfi|IN.mfm OUT.d88

MAME keeps some software-list disks as MFI, which neither CSP nor the core reads, and floptool can't write D88 (its
MFM output of F-2 Grand Prix holds only 40 cylinders at half-track steps: the MFI's form factor is 0, unknown). An
MFI track is a zlib-packed list of flux transitions at angular positions (1/200,000,000 of a turn: 2000 = one 2 us
2DD MFM cell); they are turned into cells here. Then each track's cell stream is walked: MFM address marks (A1 A1 A1 with the missing
clock, 4489h) then FE (ID: C H R N + CRC) or FB/F8 (data, 128 << N bytes + CRC), and FM marks (ID FE / data FB/F8
with clock C7, cells at half the MFM rate). Sectors are written in the order they pass the head, with their density
(D88 +6: 40h = FM), deleted mark and CRC status (A0h ID error, B0h data error), which is what CSP's (and the core's)
rotation model needs. An ID with no data field is kept as a "record not found" sector (status F0h, no data).
"""
import struct, sys, zlib


def crc16(data, crc=0xFFFF):
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def bits_of(buf):
    return ''.join(format(b, '08b') for b in buf)


def mfm_bytes(cells, pos, n):
    """n data bytes from the MFM cell string at pos (cell pairs: clock, data)."""
    out = bytearray()
    for i in range(n):
        s = cells[pos + 16 * i: pos + 16 * i + 16]
        if len(s) < 16:
            break
        out.append(int(s[1::2], 2))
    return bytes(out)


def fm_bytes(cells, pos, n):
    """n data bytes from FM recorded at half the cell rate: each FM cell is two MFM cells (1 -> '10' or '01')."""
    out = bytearray()
    for i in range(n):
        s = cells[pos + 32 * i: pos + 32 * i + 32]
        if len(s) < 32:
            break
        fm = ''.join('1' if '1' in s[k:k + 2] else '0' for k in range(0, 32, 2))
        out.append(int(fm[1::2], 2))
    return bytes(out)


def decode_track(cells):
    marks = []  # (cell position, density, mark byte, position after the mark)
    sync = '0100010010001001'
    p = cells.find(sync * 3)
    while p >= 0:
        q = p + 48
        m = mfm_bytes(cells, q, 1)
        if m and m[0] in (0xFE, 0xFB, 0xF8):
            marks.append((p, 'mfm', m[0], q + 16))
        p = cells.find(sync * 3, p + 48)
    # FM: clock C7 with data FE/FB/F8 -> 16 FM cells; each FM cell is 2 cells here
    for mark in (0xFE, 0xFB, 0xF8):
        fm = ''.join(c + d for c, d in zip(format(0xC7, '08b'), format(mark, '08b')))
        pat = ''.join('10' if c == '1' else '00' for c in fm)
        for shift in (0, 1):
            pp = ('0' * shift) + pat
            p = cells.find(pp)
            while p >= 0:
                marks.append((p + shift, 'fm', mark, p + shift + 32))
                p = cells.find(pp, p + 32)
    marks.sort()
    sectors, i = [], 0
    while i < len(marks):
        pos, den, m, after = marks[i]
        if m != 0xFE:
            i += 1
            continue
        get = mfm_bytes if den == 'mfm' else fm_bytes
        idf = get(cells, after, 6)
        pre = b'\xA1\xA1\xA1\xFE' if den == 'mfm' else b'\xFE'
        id_ok = len(idf) == 6 and crc16(pre + idf[:4]) == (idf[4] << 8 | idf[5])
        c, h, r, n = idf[:4]
        sec = dict(pos=pos, den=den, c=c, h=h, r=r, n=n, data=b'', status=0xF0, deleted=False)
        # the data mark must follow within ~ 50 bytes and before the next ID
        lim = after + (50 * 16 if den == 'mfm' else 50 * 32)
        j = i + 1
        while j < len(marks) and marks[j][0] < lim and marks[j][2] == 0xFE:
            j += 1
        if j < len(marks) and marks[j][0] < lim and marks[j][1] == den and marks[j][2] in (0xFB, 0xF8):
            size = 128 << min(n, 7)
            body = get(cells, marks[j][3], size + 2)
            dpre = (b'\xA1\xA1\xA1' if den == 'mfm' else b'') + bytes([marks[j][2]])
            ok = len(body) == size + 2 and crc16(dpre + body[:size]) == (body[size] << 8 | body[size + 1])
            sec.update(data=body[:size], deleted=marks[j][2] == 0xF8,
                       status=0xA0 if not id_ok else (0x10 if marks[j][2] == 0xF8 else 0) | (0 if ok else 0xB0))
            if not id_ok:
                sec['status'] = 0xA0
        elif not id_ok:
            sec['status'] = 0xA0
        sectors.append(sec)
        i += 1
    return sectors


def mfi_tracks(d, cell=2000):
    """{(cyl, head): cell string} from an MFI image (full-track entries only)."""
    cyl, heads = struct.unpack_from('<II', d, 16)
    res, cyl = cyl >> 30, cyl & 0x3FFFFFFF
    tracks = {}
    for k in range((cyl << res) * heads):
        off, csize, usize, _ = struct.unpack_from('<IIII', d, 32 + 16 * k)
        c, h = divmod(k, heads)
        if c % (1 << res) or not usize:
            continue
        raw = zlib.decompress(d[off:off + csize])
        t, last, out = 0, None, []
        for (v,) in struct.iter_unpack('<I', raw):
            t += v & 0x0FFFFFFF
            if v >> 28 == 0:                       # MG_F: flux transition
                if last is not None:
                    n = max(1, round((t - last) / cell))
                    out.append('0' * (n - 1) + '1')
                last = t
        tracks[(c >> res, h)] = ''.join(out)
    return cyl, heads, tracks


def main():
    src, dst = sys.argv[1], sys.argv[2]
    d = open(src, 'rb').read()
    if d.startswith(b'MAMEFLOPPYIMAGE\0'):
        ntrk, nside, tracks = mfi_tracks(d)
    elif d.startswith(b'HXCMFM\0'):
        ntrk, nside = struct.unpack_from('<H', d, 7)[0], d[9]
        tlist = struct.unpack_from('<I', d, 15)[0]
        tracks = {}
        for k in range(ntrk * nside):
            t, s, size, off = struct.unpack_from('<HBII', d, tlist + 11 * k)
            tracks[(t, s)] = bits_of(d[off:off + size])
    else:
        sys.exit('not an MFI or HxC MFM image')
    out_tracks, report = [], []
    for t in range(min(ntrk, 82)):
        for s in range(nside):
            cells = tracks.get((t, s), '')
            secs = decode_track(cells + cells[:4096])     # wrap: a sector across the index
            seen, uniq = set(), []
            for x in secs:
                if x['pos'] >= len(cells):
                    continue
                uniq.append(x)
            body = bytearray()
            for x in uniq:
                body += struct.pack('<BBBBHBBB5xH', x['c'], x['h'], x['r'], x['n'], len(uniq),
                                    0x40 if x['den'] == 'fm' else 0, 0x10 if x['deleted'] else 0, x['status'],
                                    len(x['data'])) + x['data']
            out_tracks.append(bytes(body))
            odd = [(x['r'], x['n'], x['den'], hex(x['status'])) for x in uniq
                   if x['status'] or x['den'] == 'fm' or x['n'] != 1]
            report.append('track %2d.%d: %2d sectors%s' % (t, s, len(uniq), (' odd ' + str(odd)) if odd else ''))
    offs, pos = [], 0x2B0
    for b in out_tracks:
        offs.append(pos if b else 0)
        pos += len(b)
    name = src.rsplit('/', 1)[-1][:16].encode('ascii', 'replace')
    header = name.ljust(17, b'\0') + bytes(9) + bytes([0, 0x10]) + struct.pack('<I', pos)
    header += b''.join(struct.pack('<I', o) for o in (offs + [0] * 164)[:164])
    open(dst, 'wb').write(header + b''.join(out_tracks))
    print('\n'.join(report))


if __name__ == '__main__':
    main()
