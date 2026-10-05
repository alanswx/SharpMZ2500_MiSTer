#!/bin/bash
# Regression tests for the MZ-2500 simulation. Run from verilator/ (make test).
#
# Bootstrap tests (the machine is still a test pattern):
#   pattern_400   400-line timing: 640x400 frames; frame hash at frame 60 matches tests/expected/pattern_400.txt
#   pattern_200   200-line timing: 640x200 frames; frame hash at frame 30
#   cpu_alive     the T80 stub program OUTs 00, 01, 02, 03 to port 00 within 60 frames
#
# Planned (TODO.md): ipl_boot (IPL first screen, compared with the reference emulator), kb_*, fdd_*, etc.
# Tests run in parallel; each writes to out/test/<name>.log. Set UPDATE=1 to rewrite the expected files.

cd "$(dirname "$0")"
BIN=${BIN:-./obj_dir_headless/Vtop}
OUT=${OUT:-out/test}
EXP=tests/expected
mkdir -p "$OUT"

pids=(); names=()
run() {   # run NAME ARGS...
    local name=$1; shift
    ( $BIN --quiet --out "$OUT/$name" "$@" > "$OUT/$name.out" 2> "$OUT/$name.log" ) &
    pids+=($!); names+=("$name")
}

run pattern_400 --lines 400 --stop-at-frame 60 --frame-log "$OUT/pattern_400.csv"
run pattern_200 --lines 200 --stop-at-frame 30 --frame-log "$OUT/pattern_200.csv"
run cpu_alive   --stop-at-frame 60 --trace-io "$OUT/cpu_alive.csv"

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

check pattern_400 "$(hash_at "$OUT/pattern_400.csv" 60)"
check pattern_200 "$(hash_at "$OUT/pattern_200.csv" 30)"
check cpu_alive   "$(awk -F, 'NR > 1 && $3 == "00" { printf "%s ", $4 }' "$OUT/cpu_alive.csv" | head -c 12)"

exit $fail
