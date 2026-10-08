#!/usr/bin/env python3
"""Write MGL launchers for the MZ-2500 core (MiSTer _Computer/_SharpMZ2500/*.mgl).

  tools/make_mgls.py OUTDIR GAMESDIR

GAMESDIR is the core's games folder layout (as on the SD card, games/SharpMZ2500): disks/*.d88 and tapes/*.mzt.
Every disk gets an MGL that mounts it in drive 1; a disk named *_Program.d88 with a matching *_User.d88 gets one
MGL with both drives (e.g. Ys III); every tape gets an MGL that loads it (set the boot mode in the OSD for
MZ-2000/80B tapes). Paths in the MGLs are relative to games/SharpMZ2500.
"""
import os, sys

out, games = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)


def mgl(name, files):
    body = ''.join('  <file delay="1" type="%s" index="%d" path="%s"/>\n' % f for f in files)
    with open(os.path.join(out, name + '.mgl'), 'w') as f:
        f.write('<mistergamedescription>\n  <rbf>_Computer/SharpMZ2500</rbf>\n' + body + '</mistergamedescription>\n')
    print(name)


disks = sorted(f for f in os.listdir(os.path.join(games, 'disks')) if f.lower().endswith('.d88'))
for d in disks:
    stem = d[:-4]
    if stem.endswith('_User'):
        continue
    if stem.endswith('_Program') and stem[:-8] + '_User.d88' in disks:
        mgl(stem[:-8].replace('_', ' '), [('s', 0, 'disks/' + d), ('s', 1, 'disks/' + stem[:-8] + '_User.d88')])
    else:
        mgl(stem.replace('_', ' '), [('s', 0, 'disks/' + d)])
tdir = os.path.join(games, 'tapes')
for t in sorted(os.listdir(tdir)) if os.path.isdir(tdir) else []:
    if t.lower().endswith('.mzt'):
        mgl('Tape ' + t[:-4].replace('_', ' '), [('f', 1, 'tapes/' + t)])
