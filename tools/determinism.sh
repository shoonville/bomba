#!/bin/sh
# Determinism harness (NETPLAN.md §3, §11): the same seeded per-tick input log must produce the
# same per-tick trajectory at 60 fps and at 240 fps. Runs the arena offline (host + bots, all
# inputs scripted), twice, then diffs the trajectory CSVs (tools/report.gd traj_diff; no Python
# needed). Exit 1 on any difference.
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
SEED="${SEED:-4242}"
TICKS="${TICKS:-600}"
BOTS="${BOTS:-3}"
OUT="${OUT:-reports}"
PORT="${PORT:-27101}"
mkdir -p "$OUT"
run() {
  fps="$1"; label="$2"
  "$GODOT" --headless --fixed-fps "$fps" --path . -- --host --port="$PORT" --bots="$BOTS" --start --scripted \
    --seed="$SEED" --soak_ticks="$TICKS" --report="$label" --report_dir="$(pwd)/$OUT" --log=2 \
    > "$OUT/$label.log" 2>&1 || true
}
echo "determinism: seed=$SEED ticks=$TICKS bots=$BOTS"
run 60 det_60
run 240 det_240
# Compare the overlapping tick range (both runs record from the start tick of the minigame).
set +e
"$GODOT" --headless --path . --script tools/report.gd -- traj_diff "$OUT/det_60_traj.csv" "$OUT/det_240_traj.csv" \
  > "$OUT/det_diff.txt" 2>&1
code=$?
grep -E "^(compared|  peer|PASS|FAIL)" "$OUT/det_diff.txt"
exit $code
