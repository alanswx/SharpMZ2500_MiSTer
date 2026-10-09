#!/bin/bash
# Build boot.rom for the MZ-2500 core (and the sim's --rom) from the user's own ROM dumps.
#
#   tools/make_bootrom.sh IPL.ROM KANJI.ROM [out/boot.rom [IPL2520.ROM]]
#
# Layout (docs/roms.md): 000000 IPL 32 KB, 008000 the MZ-2520 IPL (OSD Model = MZ-2520; FFh if not given), 010000 kanji
# ROM 256 KB. 320 KB total.
# Later phases append the dictionary, phone and kanji2 ROMs. CRCs are checked against MAME's set.
# Put the result in games/SharpMZ2500/boot.rom on the MiSTer SD card: the menu loads it when the core starts.
set -e
IPL=${1:?usage: $0 IPL.ROM KANJI.ROM [boot.rom]}
KANJI=${2:?usage: $0 IPL.ROM KANJI.ROM [boot.rom]}
OUT=${3:-boot.rom}
IPL2520=${4:-}

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

python3 - "$IPL" "$KANJI" "$OUT" "$IPL2520" <<'PY'
import sys
ipl, kanji, out = (open(sys.argv[1], 'rb').read(), open(sys.argv[2], 'rb').read(), sys.argv[3])
ipl2520 = open(sys.argv[4], 'rb').read() if sys.argv[4] else b'\xff' * 0x8000
img = ipl + ipl2520 + kanji
open(out, 'wb').write(img)
print('%s: %d bytes' % (out, len(img)))
PY
