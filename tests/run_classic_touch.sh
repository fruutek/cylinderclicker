#!/usr/bin/env bash
# The classic game by injected touch at the Pixel 9 Pro's screen shape.
# Usage: tests/run_classic_touch.sh [godot] [screenshot-dir]
set -euo pipefail
GODOT="${1:-godot}"
SHOTS="${2:-}"
cd "$(dirname "$0")/.."
DIR="$(mktemp -d)"
xvfb-run -a -s "-screen 0 1428x640x24" "$GODOT" --path . --rendering-driver opengl3 --resolution 1428x640 -- \
  --fresh --autostart --touch-ui --safe-inset=38,0 "--save-path=$DIR/save.json" --root-bot=res://tests/classic_touch_bot.gd \
  ${SHOTS:+"--capture=$SHOTS"} 2>&1 | grep -E "^  (ok|FAIL)|CLASSIC TOUCH|SCRIPT ERROR" || true
