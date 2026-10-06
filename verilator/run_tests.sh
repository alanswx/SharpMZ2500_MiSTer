#!/bin/bash
# Regression tests for the MZ-2500 simulation. Run from verilator/ (make test).
#
#   ipl_400   real IPL, 400-line monitor, no media: "loading error / Press F or C" screen. Frame hash at frame 400.
#             The picture is identical, pixel for pixel, to BubiZ-2500's (CSP core) screenshot of the same screen
#             (refs/compare/bubiz_ipl_nodisk_f600.png).
#   ipl_200   the same with the 200-line switch, frame 450; identical to MAME's 640x200 screenshot
#             (refs/compare/mame_ipl_nodisk_f1500.png).
#
#   ys3_1000  (GAMES=1 only, about 8 minutes) Ys III from its two D88 disks: frame 1000 hash, in the scrolling intro.
#             Needs the disks in ../software/archive.org/mz-2500/extracted/ (docs/software.md); read-only.
#
# Needs the IPL and kanji ROMs in ../software/roms/extracted/ (docs/roms.md), or set ROM=path/to/boot.rom.
# Tests run in parallel; each writes to out/test/<name>.log. Set UPDATE=1 to rewrite the expected files.
# Each IPL test takes about 3 minutes (the sim runs at about 2.3 frames per second).

cd "$(dirname "$0")"
BIN=${BIN:-./obj_dir_headless/Vtop}
OUT=${OUT:-out/test}
EXP=tests/expected
ROMARG=()
[ -n "$ROM" ] && ROMARG=(--rom "$ROM")
mkdir -p "$OUT"

pids=(); names=()
run() {   # run NAME ARGS...
    local name=$1; shift
    ( $BIN --quiet "${ROMARG[@]}" --out "$OUT/$name" "$@" > "$OUT/$name.out" 2> "$OUT/$name.log" ) &
    pids+=($!); names+=("$name")
}

run ipl_400 --lines 400 --stop-at-frame 400 --screenshot 400 --frame-log "$OUT/ipl_400.csv"
run ipl_200 --lines 200 --stop-at-frame 450 --screenshot 450 --frame-log "$OUT/ipl_200.csv"
YS3="../software/archive.org/mz-2500/extracted/MZ2500 同人自作フリーゲームセット (起動確認済)"
if [ -n "$GAMES" ]; then
    run ys3_1000 --fdd "$YS3/Ys'3 (19xx)(-)(Program).D88" --fdd-b "$YS3/Ys'3 (19xx)(-)(User).D88" --fdd-readonly \
        --stop-at-frame 1000 --screenshot 1000 --frame-log "$OUT/ys3_1000.csv"
fi

fail=0
for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then echo "FAIL ${names[$i]} (exit status; see $OUT/${names[$i]}.log)"; fail=1; fi
done

# Frame hash at a given frame from a --frame-log CSV.
hash_at() { awk -F, -v f="$2" '$1 == f { print $2 }' "$1"; }

check() {   # check NAME ACTUAL
    local name=$1 actual=$2
    if [ -n "$UPDATE" ]; then echo "$actual" > "$EXP/$name.txt"; echo "UPDATED $name"; return; fi
    if [ "$actual" == "$(cat "$EXP/$name.txt" 2>/dev/null)" ]; then echo "PASS $name"
    else echo "FAIL $name: got '$actual', expected '$(cat "$EXP/$name.txt" 2>/dev/null)'"; fail=1; fi
}

check ipl_400 "$(hash_at "$OUT/ipl_400.csv" 400)"
check ipl_200 "$(hash_at "$OUT/ipl_200.csv" 450)"
[ -n "$GAMES" ] && check ys3_1000 "$(hash_at "$OUT/ys3_1000.csv" 1000)"

exit $fail
