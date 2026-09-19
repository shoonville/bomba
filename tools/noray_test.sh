#!/bin/sh
# Friend-code join through a noray relay (default: the public tomfol.io instance). Starts a host
# that registers online, reads its code from the log, then joins with a second process and runs a
# short soak. Usage: tools/noray_test.sh [seconds] [relay|nat]
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
SECONDS_="${1:-20}"
MODE="${2:-nat}"
OUT="${OUT:-reports}"
mkdir -p "$OUT"
"$GODOT" --headless --path . -- --host_online --bots=1 --start --expect=1 --autoplay --seed=9 \
  --soak="$SECONDS_" --report=noray_host --report_dir="$(pwd)/$OUT" --log=2 > "$OUT/noray_host.log" 2>&1 &
HOST_PID=$!
CODE=""
i=0
while [ -z "$CODE" ] && [ "$i" -lt 150 ]; do
  sleep 0.2
  CODE=$(grep -h "HOST_CODE=" "$OUT/noray_host.log" 2>/dev/null | head -1 | sed 's/.*HOST_CODE=//')
  i=$((i + 1))
done
if [ -z "$CODE" ]; then
  echo "host never got a code; log tail:"; tail -5 "$OUT/noray_host.log"; kill $HOST_PID 2>/dev/null || true; exit 1
fi
echo "host code: $CODE (mode $MODE)"
RELAY=""
[ "$MODE" = "relay" ] && RELAY="--relay"
"$GODOT" --headless --path . -- --join_code="$CODE" $RELAY --autoplay --soak="$SECONDS_" \
  --report=noray_client --report_dir="$(pwd)/$OUT" --log=2 > "$OUT/noray_client.log" 2>&1 || true
wait $HOST_PID || true
echo "--- host ---"; grep -h -E "\[net\]|\[session\]|Setup:|finished|ERROR" "$OUT/noray_host.log" | head -8
echo "--- client ---"; grep -h -E "\[net\]|\[session\]|Setup:|finished|ERROR|Connect|failed" "$OUT/noray_client.log" | head -10
python3 tools/soak_report.py "$OUT" noray 2>/dev/null | grep -E "client #|mispredict|confirm" || true
