#!/bin/bash
# Run hardware test plans on a MiSTer and fetch the screenshots.
#
#   tools/mister_run.sh HOST PLAN.txt [PLAN.txt...]      e.g. tools/mister_run.sh mister14 tools/mister_tests/ipl.txt
#
# Copies tools/mister_test.py and the plans to /root/mzt on HOST, runs them in order, then copies the screenshots
# taken during the run into verilator/out/hw/<run>/.
set -e
HOST=${1:?usage: $0 HOST PLAN...}; shift
cd "$(dirname "$0")/.."
RUN=$(date +%Y%m%d_%H%M%S)
OUT=verilator/out/hw/$RUN
mkdir -p "$OUT"
ssh "$HOST" 'mkdir -p /root/mzt && touch /root/mzt/.start'
scp -q tools/mister_test.py "$@" "$HOST:/root/mzt/"
for p in "$@"; do
    echo "== $(basename "$p")"
    ssh "$HOST" "cd /root/mzt && python3 mister_test.py $(basename "$p")" | tee -a "$OUT/run.log"
done
ssh "$HOST" 'cd /media/fat/screenshots/SharpMZ2500 && find . -newer /root/mzt/.start -name "*.png" | tar cf - -T -' | tar xf - -C "$OUT"
ls "$OUT"
