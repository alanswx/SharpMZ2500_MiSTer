#!/usr/bin/env python3
"""Convert an MZ-80B/MZ-2000/MZ-2200 cassette WAV to an MZT image (the core's data recorder plays MZT only).

  tools/wav2mzt.py IN.wav OUT.mzt

MZ-80B format (CSP datarec.cpp for _MZ80B/_MZ2000, rtl/mz2500_cmt.sv): a bit is one high/low cycle, long (about
667 us) = 1, short (about 333 us) = 0. A record is a gap of short bits, a tape mark (40 long + 40/41 short before the
header, 20 + 20/21 before the data), then bytes as a long start bit and 8 bits MSB first, then a 16-bit count of the
1 bits. Every header (128 bytes) and data block (size from header bytes 12h-13h) found is written back to back, as an
MZT. Records whose count doesn't match are reported and kept. Loaders with their own tape format (turbo loaders,
protection) can't be converted this way.
"""
import struct, sys, wave


def periods(path):
    w = wave.open(path, 'rb')
    ch, sw, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
    raw = w.readframes(n)
    if sw == 1:
        s = [b - 128 for b in raw[::ch]]
    elif sw == 2:
        s = list(struct.unpack('<%dh' % (len(raw) // 2), raw))[::ch]
    else:
        sys.exit('unsupported sample width %d' % sw)
    # remove the DC level (analogue recordings wander) with a running mean over about 1.5 ms
    win = max(3, int(rate * 0.0015))
    acc, hp = 0, []
    for i, x in enumerate(s):
        acc += x - (s[i - win] if i >= win else 0)
        hp.append(x - acc / min(i + 1, win))
    s = hp
    peak = max(1, max(abs(x) for x in s))
    best = None
    for pol in (1, -1):                      # a bit is high then low; recordings can be inverted
        hi, lo = peak * 0.05, -peak * 0.05   # hysteresis around zero
        state, last, out = 0, None, []
        for i, x in enumerate(s):
            x *= pol
            if state <= 0 and x > hi:
                if last is not None:
                    out.append((i - last) * 1e6 / rate)      # rising edge to rising edge, in us
                last, state = i, 1
            elif state >= 0 and x < lo:
                state = -1
        # cycles between the short (~333 us) and long (~667 us) lengths come from reading across bit boundaries
        mixed = sum(1 for p in out if 430 < p < 570)
        if best is None or mixed < best[0]:
            best = (mixed, out)
    return best[1]


def bits(per):
    # threshold halfway between the short and long cycle lengths, found from the data (tapes run fast or slow)
    srt = sorted(p for p in per if 150 < p < 1500)
    short = srt[len(srt) // 4]
    long_ = [p for p in srt if p > short * 1.5]
    long_ = long_[len(long_) // 2] if long_ else short * 2
    th = (short + long_) / 2
    return ''.join('1' if p > th else '0' for p in per), short, long_


def read_block(b, p, want):
    """want bytes and the 16-bit count from bit p: (body, count matches, next bit) or None."""
    data = bytearray()
    for _ in range(want + 2):
        if p + 9 > len(b) or b[p] != '1':
            return None
        data.append(int(b[p + 1:p + 9], 2))
        p += 9
    body, cnt = bytes(data[:want]), data[want] << 8 | data[want + 1]
    return body, sum(bin(x).count('1') for x in body) == cnt, p


def decode(b):
    recs, i = [], 0
    while True:
        # tape mark: >= 15 long followed by >= 15 short
        j = b.find('1' * 15 + '0' * 15, i)
        if j < 0:
            break
        while j > i and b[j - 1] == '1':            # back to the start of the long run
            j -= 1
        k = j
        while k < len(b) and b[k] == '1':
            k += 1
        while k < len(b) and b[k] == '0':
            k += 1
        nlong = k - j - b[j:k].count('0')
        want = 128 if nlong >= 30 else None          # header after the long mark; data after the short one
        if want is None:
            if not recs or recs[-1][0] != 'hdr':
                i = k
                continue
            hdr = recs[-1][1]
            want = hdr[0x12] | hdr[0x13] << 8
        # the MZ-2500/2200 recordings have one more long bit after the mark than CSP's MZ-80B encoding: try both
        best = None
        for start in (k, k + 1):
            r = read_block(b, start, want)
            if r and (best is None or (r[1] and not best[1])):
                best = r
        if best is None:
            i = k
            continue
        body, good, p = best
        recs.append(('hdr' if want == 128 and nlong >= 30 else 'dat', body, good))
        i = p
    return recs


def main():
    per = periods(sys.argv[1])
    b, short, long_ = bits(per)
    recs = decode(b)
    out, ok, last = bytearray(), True, None
    for kind, body, good in recs:
        if kind == 'hdr':
            if body == last:                     # a repeated header copy
                continue
            last = body
            name = body[1:17].split(b'\r')[0].decode('latin-1')
            print('header %-16s size %04X load %04X exec %04X%s' % (name, body[0x12] | body[0x13] << 8,
                  body[0x14] | body[0x15] << 8, body[0x16] | body[0x17] << 8, '' if good else '  CHECKSUM ERROR'))
        else:
            print('  data %d bytes%s' % (len(body), '' if good else '  CHECKSUM ERROR'))
        ok &= good
        out += body
    print('cycles: short %.0f us, long %.0f us; %d records%s' % (short, long_, len(recs), '' if ok else '; errors'))
    if not recs:
        sys.exit('no records found (custom tape format?)')
    open(sys.argv[2], 'wb').write(out)
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
