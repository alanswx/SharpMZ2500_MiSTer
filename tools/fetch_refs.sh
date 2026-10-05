#!/bin/bash
# Re-fetch the reference material into refs/ (gitignored). Idempotent: existing clones/files are kept.
#
#   tools/fetch_refs.sh                 emulator sources, FPGA blocks, docs, BubiZ-2500 release
#   tools/fetch_refs.sh --mame-full     also expand the MAME clone to the full tree (needed to build ./mz2500)
#   tools/fetch_refs.sh --roms DIR      copy MZ-2500 ROM zips/files from DIR into software/roms/ and verify CRC32s
#   tools/fetch_refs.sh --software      download the archive.org 'mz-2500' set into software/archive.org/
#
# ROMs are never downloaded: they are Sharp's copyright. See docs/roms.md for where to get them.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REFS="$ROOT/refs"
SW="$ROOT/software"
MAME_FULL=0
ROMDIR=""
SOFTWARE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --mame-full) MAME_FULL=1 ;;
    --roms) ROMDIR="$2"; shift ;;
    --software) SOFTWARE=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown option $1" >&2; exit 1 ;;
  esac
  shift
done

mkdir -p "$REFS"/{mame,csp,fpga/rtc,docs/maroon,docs/eaw,docs/web,docs/takeda,compare} "$SW"

clone() {  # clone URL DIR [extra git args...]
  local url="$1" dir="$2"; shift 2
  if [ -d "$dir/.git" ]; then
    echo "have $dir"
  else
    echo "clone $url -> $dir"
    git clone --depth 1 "$@" "$url" "$dir"
  fi
}

get() {  # get URL FILE
  local url="$1" file="$2"
  if [ -s "$file" ]; then
    echo "have $file"
  else
    echo "get $url"
    mkdir -p "$(dirname "$file")"
    curl -fsSL -m 600 -A 'Mozilla/5.0' -o "$file" "$url" || { echo "  failed: $url" >&2; rm -f "$file"; }
  fi
}

# ---------------------------------------------------------------- MAME (BSD-3 driver, GPL-2.0+ overall)
if [ ! -d "$REFS/mame/src-tree/.git" ]; then
  git clone --depth 1 --filter=blob:none --sparse https://github.com/mamedev/mame.git "$REFS/mame/src-tree"
  (cd "$REFS/mame/src-tree" && git sparse-checkout set --no-cone src/mame/sharp hash/mz2500_flop.xml hash/mz2000_flop.xml)
fi
if [ "$MAME_FULL" = 1 ]; then
  (cd "$REFS/mame/src-tree" && git sparse-checkout disable)
  echo "build: cd refs/mame/src-tree && make SUBTARGET=mz2500 SOURCES=src/mame/sharp/mz2500.cpp REGENIE=1 -j\$(sysctl -n hw.ncpu)"
fi
for f in src/mame/sharp/mz2500.cpp src/mame/sharp/mz2500.h hash/mz2500_flop.xml hash/mz2000_flop.xml; do
  cp -p "$REFS/mame/src-tree/$f" "$REFS/mame/"
done
mkdir -p "$REFS/mame/run"
cp -p "$ROOT/tools/mame_snap.lua" "$REFS/mame/run/snap.lua"

# ---------------------------------------------------------------- Common Source Code Project (GPLv2)
get https://takeda-toshiya.my.coocan.jp/common/source.7z "$REFS/csp/source.7z"
if [ -s "$REFS/csp/source.7z" ] && [ ! -d "$REFS/csp/takeda/source" ]; then
  mkdir -p "$REFS/csp/takeda" && (cd "$REFS/csp/takeda" && 7z x -y ../source.7z >/dev/null)
fi
clone https://github.com/Artanejp/common_source_project-fm7.git "$REFS/csp/common_source_project-fm7"
clone https://github.com/bubio/BubiZ-2500.git "$REFS/csp/BubiZ-2500"

# BubiZ-2500 release (CSP core, headless mode) for macOS Apple Silicon
REL="$REFS/csp/bubiz-release"
if [ ! -d "$REL/BubiZ-2500.app" ] && [ "$(uname -s)" = Darwin ] && command -v gh >/dev/null; then
  mkdir -p "$REL"
  gh release download v1.0.0 -R bubio/BubiZ-2500 -p '*macos-apple-silicon.dmg' -p SHA256SUMS.txt -D "$REL" --clobber
  (cd "$REL" && grep apple-silicon SHA256SUMS.txt | shasum -a 256 -c -)
  hdiutil attach -nobrowse -readonly -mountpoint "$REL/mnt" "$REL"/BubiZ-2500-*-macos-apple-silicon.dmg >/dev/null
  cp -R "$REL/mnt/BubiZ-2500.app" "$REL/"
  hdiutil detach "$REL/mnt" >/dev/null
  xattr -cr "$REL/BubiZ-2500.app"
fi

# ---------------------------------------------------------------- FPGA blocks
clone https://github.com/jotego/jt12.git "$REFS/fpga/jt12"
(cd "$REFS/fpga/jt12" && git submodule update --init --depth 1 jt49)
X68=https://raw.githubusercontent.com/MiSTer-devel/X68000_MiSTer/master/rtl/rtc
get "$X68/rp5c15.vhd"  "$REFS/fpga/rtc/x68000_rp5c15.vhd"
get "$X68/rtcbody.vhd" "$REFS/fpga/rtc/x68000_rtcbody.vhd"
get "$X68/rtc.qip"     "$REFS/fpga/rtc/x68000_rtc.qip"
get https://raw.githubusercontent.com/MiSTer-devel/MSX_MiSTer/master/rtl/peripheral/rtc.vhd "$REFS/fpga/rtc/msx_rtc.vhd"

# ---------------------------------------------------------------- Documentation
M=http://www.maroon.dti.ne.jp/youkan/mz2500
for p in index.html iomap.html ioframe.html iomenu.html disp.html kbd.html dipsw.html sectorread.html videotiming.html SVC.INC \
         kbd_a1.jpg kbd_a2.jpg kbd_timing.png MZ25KBDA.png; do
  get "$M/$p" "$REFS/docs/maroon/$p"
done
get http://www.maroon.dti.ne.jp/youkan/CSCP/index.html "$REFS/docs/maroon/CSCP_index.html"
E=https://eaw.app/Downloads/Manuals/Sharp
for f in MZ2500_IO_Map MZ2500_Schematics MZ2500_Keyboard_Protocol MZ2500_Video_Capabilities MZ2500_Document \
         MZ2500_UserManual MZ2500_BASIC_M25_Manual MZ2500_BASIC_S25_Manual MZ2500_SuperMZ_Magazine MZ2500_Telephone_Manual; do
  get "$E/$f.pdf" "$REFS/docs/eaw/$f.pdf"
done
get https://eaw.app/sharpmz-2500-specifications/ "$REFS/docs/web/eaw_sharpmz-2500-specifications.html"
get https://eaw.app/sharpmz-2500-manuals/        "$REFS/docs/web/eaw_sharpmz-2500-manuals.html"
get https://en.wikipedia.org/wiki/MZ-2500        "$REFS/docs/web/wikipedia_en_MZ-2500.html"
get https://ja.wikipedia.org/wiki/MZ-2500        "$REFS/docs/web/wikipedia_ja_MZ-2500.html"
T=https://takeda-toshiya.my.coocan.jp
get "$T/mz2500/index.html"  "$REFS/docs/takeda/takeda_mz2500.html"
for d in diary.txt diary1.txt diary2.txt diary3.txt; do get "$T/mz2500/$d" "$REFS/docs/takeda/takeda_mz2500_$d"; done
get "$T/common/index.html"  "$REFS/docs/takeda/takeda_common.html"

# ---------------------------------------------------------------- Software (archive.org only)
if [ "$SOFTWARE" = 1 ]; then
  A="$SW/archive.org/mz-2500"
  get "https://archive.org/download/mz-2500/MZ2500%20%E5%90%8C%E4%BA%BA%E8%87%AA%E4%BD%9C%E3%83%95%E3%83%AA%E3%83%BC%E3%82%B2%E3%83%BC%E3%83%A0%E3%82%BB%E3%83%83%E3%83%88%20(%E8%B5%B7%E5%8B%95%E7%A2%BA%E8%AA%8D%E6%B8%88).rar" \
      "$A/MZ2500_doujin_free_games.rar"
  if [ -s "$A/MZ2500_doujin_free_games.rar" ] && [ ! -d "$A/extracted" ]; then
    mkdir -p "$A/extracted" && (cd "$A/extracted" && unrar x -o+ -inul ../MZ2500_doujin_free_games.rar)
  fi
fi

# ---------------------------------------------------------------- ROMs (local copy only)
if [ -n "$ROMDIR" ]; then
  mkdir -p "$SW/roms/zips" "$SW/roms/extracted"
  find "$ROMDIR" -maxdepth 1 -type f \( -iname '*.zip' -o -iname '*.rom' \) -exec cp -p {} "$SW/roms/zips/" \;
  for z in "$SW"/roms/zips/*.zip; do
    [ -e "$z" ] || continue
    n="$(basename "$z" .zip)"; mkdir -p "$SW/roms/extracted/$n"; unzip -o -q "$z" -d "$SW/roms/extracted/$n"
  done
  echo "CRC32 check against MAME (docs/roms.md):"
  python3 - "$SW/roms" <<'EOF'
import os, sys, zlib
known = {'7a659f20': 'ipl.rom (mz2500)', '0a126eb2': 'ipl2520.rom (mz2520)', 'a082326f': 'cg.rom',
         'dd426767': 'kanji.rom', 'eaaf20c9': 'kanji2.rom', 'aa957c2b': 'dict.rom', '8e49e4dc': 'phone.rom'}
for d, _, files in os.walk(sys.argv[1]):
    for f in sorted(files):
        if f.lower().endswith('.zip'):
            continue
        p = os.path.join(d, f)
        c = '%08x' % (zlib.crc32(open(p, 'rb').read()) & 0xffffffff)
        print('%-60s %s %s' % (os.path.relpath(p, sys.argv[1]), c, known.get(c, '')))
EOF
else
  cat <<'EOF'
ROMs are not downloaded. Copy your own dumps with:  tools/fetch_refs.sh --roms <dir with IPL.zip KANJI.zip ...>
Expected (MAME): ipl.rom 7a659f20, ipl2520.rom 0a126eb2, kanji.rom dd426767, kanji2.rom eaaf20c9, dict.rom aa957c2b, phone.rom 8e49e4dc.
Sources: your machine (Mr. Tago's dump tool), or the idealine.info sharpmz mirror ROM pages. See docs/roms.md.
EOF
fi
echo done
