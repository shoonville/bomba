#!/bin/sh
# Network soak harness (NETPLAN.md §11): one host and N clients as separate headless processes
# on this machine, every seat bot-driven, clients routed through the conditioner profile.
# Usage: tools/soak.sh [profile] [seconds] [clients] [bots]
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROFILE="${1:-bad}"
SECONDS_="${2:-30}"
CLIENTS="${3:-1}"
BOTS="${4:-1}"
PORT="${PORT:-27015}"
SEED="${SEED:-7}"
OUT="${OUT:-reports}"
LABEL="${LABEL:-soak_$PROFILE}"
LOG="${LOG:-2}"
mkdir -p "$OUT"
echo "soak: profile=$PROFILE seconds=$SECONDS_ clients=$CLIENTS bots=$BOTS port=$PORT seed=$SEED"
"$GODOT" --headless --path . -- --host --port="$PORT" --bots="$BOTS" --start --expect="$CLIENTS" --autoplay \
  --seed="$SEED" --soak="$SECONDS_" --report="${LABEL}_host" --report_dir="$(pwd)/$OUT" --log="$LOG" \
  > "$OUT/${LABEL}_host.log" 2>&1 &
HOST_PID=$!
sleep 2
i=1
PIDS=""
while [ "$i" -le "$CLIENTS" ]; do
  "$GODOT" --headless --path . -- --join="127.0.0.1:$PORT" --conditioner="$PROFILE" --autoplay \
    --net_seed="$((SEED + i))" --soak="$SECONDS_" --report="${LABEL}_client$i" --report_dir="$(pwd)/$OUT" --log="$LOG" \
    > "$OUT/${LABEL}_client$i.log" 2>&1 &
  PIDS="$PIDS $!"
  i=$((i + 1))
done
wait $HOST_PID
for p in $PIDS; do wait "$p" || true; done
python3 tools/soak_report.py "$OUT" "$LABEL"
if [ "$LOG" -le 1 ]; then
  i=1
  while [ "$i" -le "$CLIENTS" ]; do
    python3 tools/shot_diff.py "$OUT/${LABEL}_host.log" "$OUT/${LABEL}_client$i.log" | head -1
    python3 tools/remote_diff.py "$OUT/${LABEL}_host_traj.csv" "$OUT/${LABEL}_client${i}_remote.csv" 2>/dev/null | grep -E "^peer"
    i=$((i + 1))
  done
fi
