#!/bin/bash
# Build boot.rom for the MZ-2500 core (and the sim's --rom) from the user's own ROM dumps.
#
#   tools/make_bootrom.sh IPL.ROM KANJI.ROM [out/boot.rom [IPL2520.ROM [DICT.ROM [PHONE.ROM [KANJI2.ROM]]]]]
#
# Layout (docs/roms.md): 000000 IPL 32 KB, 008000 the MZ-2520 IPL (OSD Model = MZ-2520), 010000 kanji ROM 256 KB,
# 050000 dictionary 256 KB (page 3A), 090000 phone ROM padded to 32 KB (pages 3C-3F), 098000 MZ-1R13 kanji ROM 128 KB
# (ports B8/B9): 736 KB. A ROM not given (or given as '') is FFh, as in CSP; without the last three the file stops
# after the kanji ROM (320 KB, as before). CRCs are checked against MAME's set.
# Put the result in games/SharpMZ2500/boot.rom on the MiSTer SD card: the menu loads it when the core starts.
set -e
IPL=${1:?usage: $0 IPL.ROM KANJI.ROM [boot.rom]}
KANJI=${2:?usage: $0 IPL.ROM KANJI.ROM [boot.rom]}
OUT=${3:-boot.rom}
IPL2520=${4:-}
DICT=${5:-}
PHONE=${6:-}
KANJI2=${7:-}

crc() { python3 -c "import zlib,sys; print('%08x' % zlib.crc32(open(sys.argv[1],'rb').read()))" "$1"; }
check() {   # check FILE SIZE CRC NAME
    local s; s=$(wc -c < "$1" | tr -d ' ')
    [ "$s" == "$2" ] || { echo "$4: $1 is $s bytes, expected $2" >&2; exit 1; }
    local c; c=$(crc "$1")
    [ "$c" == "$3" ] || echo "warning: $4: CRC $c, expected $3 (MAME's dump); using it anyway" >&2
}
check "$IPL" 32768 7a659f20 IPL
check "$KANJI" 262144 dd426767 kanji
[ -n "$IPL2520" ] && check "$IPL2520" 32768 0a126eb2 "MZ-2520 IPL"
[ -n "$DICT" ] && check "$DICT" 262144 aa957c2b dictionary
[ -n "$PHONE" ] && check "$PHONE" 16384 8e49e4dc phone
[ -n "$KANJI2" ] && check "$KANJI2" 131072 eaaf20c9 "MZ-1R13 kanji"

python3 - "$IPL" "$KANJI" "$OUT" "$IPL2520" "$DICT" "$PHONE" "$KANJI2" <<'PY'
import sys
ipl, kanji, out = (open(sys.argv[1], 'rb').read(), open(sys.argv[2], 'rb').read(), sys.argv[3])
opt = lambda f, size: open(f, 'rb').read().ljust(size, b'\xff') if f else b'\xff' * size
img = ipl + opt(sys.argv[4], 0x8000) + kanji
if any(sys.argv[5:8]):
    img += opt(sys.argv[5], 0x40000) + opt(sys.argv[6], 0x8000) + opt(sys.argv[7], 0x20000)
open(out, 'wb').write(img)
print('%s: %d bytes' % (out, len(img)))
PY
