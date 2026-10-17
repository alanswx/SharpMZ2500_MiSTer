#!/bin/bash
# Run hardware test plans on a MiSTer and fetch the screenshots.
#
#   tools/mister_run.sh HOST PLAN.txt [PLAN.txt...]      e.g. tools/mister_run.sh mister14 tools/mister_tests/ipl.txt
#
# Copies tools/mister_test.py and the plans to /root/mzt (MZT_DIR) on HOST and runs them there detached (nohup), so a dropped
# ssh session doesn't stop a long plan; polls until they finish, then copies the screenshots taken during the run
# into verilator/out/hw/<run>/ with the plan log. MZT_DIR sets the work directory on the MiSTer (default /root/mzt;
# use e.g. MZT_DIR=/media/fat/mzt where /root is read-only).
set -e
HOST=${1:?usage: $0 HOST PLAN...}; shift
cd "$(dirname "$0")/.."
D=${MZT_DIR:-/root/mzt}
RUN=$(date +%Y%m%d_%H%M%S)
OUT=verilator/out/hw/$RUN
mkdir -p "$OUT"
NAMES=""
for p in "$@"; do NAMES="$NAMES $(basename "$p")"; done
ssh "$HOST" "mkdir -p $D && touch $D/.start && rm -f $D/.done $D/run.log"
scp -q tools/mister_test.py "$@" "$HOST:$D/"
ssh "$HOST" "cd $D && nohup sh -c 'for p in$NAMES; do echo \"== \$p\"; python3 mister_test.py \$p; done; touch .done' > run.log 2>&1 < /dev/null &"
echo "running$NAMES on $HOST"
until ssh -o ConnectTimeout=10 "$HOST" "test -f $D/.done" 2>/dev/null; do sleep 15; done
ssh "$HOST" "cat $D/run.log" | tee "$OUT/run.log"
ssh "$HOST" "cd /media/fat/screenshots/SharpMZ2500 && find . -newer $D/.start -name '*.png' | tar cf - -T -" | tar xf - -C "$OUT"
ls "$OUT"
