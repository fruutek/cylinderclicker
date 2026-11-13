#!/usr/bin/env bash
# End-to-end check of the phone presentation with injected touch input and a
# simulated Android pause/resume lifecycle, at the Pixel 9 Pro's screen shape.
# Usage: tests/run_touch_flow.sh [godot] [screenshot-dir]
set -euo pipefail
GODOT="${1:-godot}"
SHOTS="${2:-}"
cd "$(dirname "$0")/.."
DIR="$(mktemp -d)"
SAVE="$DIR/touch_save.json"
run() {
  local phase="$1"; shift
  xvfb-run -a -s "-screen 0 1428x640x24" "$GODOT" --path . --rendering-driver opengl3 --resolution 1428x640 -- \
    --touch-ui --safe-inset=38,0 "--save-path=$SAVE" --root-bot=res://tests/touch_flow_bot.gd "--phase=$phase" \
    ${SHOTS:+"--capture=$SHOTS"} "$@" 2>&1 | grep -E "^  (ok|FAIL|viewport|rapid)|TOUCH FLOW|EXPECT|SCRIPT ERROR|at: " | grep -v "at: \(cleanup\|clear\|init\|set_use\|_free\)" || true
}
run 1
# Phase 1 ended 7220 simulated seconds ahead; reopen two hours after that.
run 2 --clock-offset=14420
