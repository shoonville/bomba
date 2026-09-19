#!/bin/sh
# One command that proves the build (DESIGN.md §8: numbers, not adjectives):
#   1. unit tests + compile-all            (tools/test.sh)
#   2. determinism, 60 vs 240 fps           (tools/determinism.sh)
#   3. a headless board match on every shipped board: 4 seats, 2 rounds, random minigames
# Prints PASS/FAIL per stage, exits non-zero on any failure. About 3 minutes.
# SOAK=1 appends the 3-seat netcode soak through the "bad" profile (another minute).
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PORT="${PORT:-27103}"   # its own port: a running game on 27015 must not fail the check
fail=0
stage() {
  if [ "$2" -eq 0 ]; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi
}

out=$(tools/test.sh 2>&1)
echo "$out" | grep -E "^=== [0-9]+ tests" | sed 's/^/      /'
echo "$out" | grep -q ", 0 failed," && echo "$out" | grep -q "(0 failed)"
stage "unit tests + compile-all" $?

out=$(tools/determinism.sh 2>&1)
echo "$out" | grep -E "compared|PASS|FAIL" | sed 's/^/      /'
echo "$out" | grep -q "^PASS"
stage "determinism 60 vs 240 fps" $?

for f in board/boards/*.json; do
  board=$(basename "$f" .json)
  log=$("$GODOT" --headless --path . -- --host --port="$PORT" --bots=3 --start --board --board_id="$board" --autoplay \
    --board_rounds=2 --board_minigame_seconds=8 --seed=3 --soak=240 --log=2 2>&1)
  echo "$log" | grep -E "minigame:|Board match finished" | sed 's/^.*\] /      /'
  echo "$log" | grep -q "Board match finished" && ! echo "$log" | grep -q -E "SCRIPT ERROR|\[ERR\]|\[WRN\]"
  ok=$?
  [ "$ok" -ne 0 ] && echo "$log" | grep -E "SCRIPT ERROR|\[ERR\]|\[WRN\]" | head -5 | sed 's/^/      /'
  stage "board '$board': 4 seats, 2 rounds, random minigames, no warnings" $ok
done

if [ "${SOAK:-0}" = "1" ]; then
  out=$(LABEL=check_bad tools/soak.sh bad 45 1 1 2>&1)
  echo "$out" | grep -E "rtt mean|mispredict|confirm_rate|outages" | sed 's/^/      /'
  echo "$out" | grep -q "confirm_rate" && ! echo "$out" | grep -q -E "SCRIPT ERROR"
  stage "netcode soak, bad profile, 3 seats" $?
fi
exit $fail
