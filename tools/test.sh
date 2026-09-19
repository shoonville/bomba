#!/bin/sh
# Re-import (refreshes the class cache for new class_name scripts) and run the unit tests.
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
"$GODOT" --headless --path . --script tools/test_runner.gd 2>&1 | grep -v -E "netfox::NetworkPerformance|NetworkSimulator|^\s*$"
