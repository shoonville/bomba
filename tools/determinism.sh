#!/bin/sh
# Determinism harness (NETPLAN.md §3, §11): the same seeded per-tick input log must produce the
# same per-tick trajectory at 60 fps and at 240 fps. Runs the arena offline (host + bots, all
# inputs scripted), twice, then diffs the trajectory CSVs. Exit 1 on any difference.
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
python3 - "$OUT/det_60_traj.csv" "$OUT/det_240_traj.csv" <<'PY'
import sys, csv
a, b = sys.argv[1], sys.argv[2]
def load(p):
    rows = {}
    with open(p) as f:
        r = csv.DictReader(f)
        for row in r:
            rows[(int(row["peer"]), int(row["tick"]))] = row
    return rows
ra, rb = load(a), load(b)
common = sorted(set(ra) & set(rb))
if not common:
    print("FAIL: no overlapping ticks (%d vs %d rows)" % (len(ra), len(rb))); sys.exit(1)
diffs = 0
first = None
for k in common:
    if any(ra[k][c] != rb[k][c] for c in ("x","y","z","health","kills","deaths","yaw")):
        diffs += 1
        if first is None:
            first = (k, ra[k], rb[k])
print("compared %d (peer,tick) rows; %d differ; ticks %d..%d" % (len(common), diffs, common[0][1], common[-1][1]))
if diffs:
    k, x, y = first
    print("first difference at peer %d tick %d:\n  60fps : %s\n  240fps: %s" % (k[0], k[1], dict(x), dict(y)))
    sys.exit(1)
print("PASS: trajectories identical to the byte")
PY
