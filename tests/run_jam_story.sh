#!/usr/bin/env bash
# The traffic-jam story at the Pixel 9 Pro's landscape screen shape: cartons piling up at the end of the conveyor,
# the belt and machines backing up, the van returning and the backlog moving again - checked on what is drawn.
# Usage: tests/run_jam_story.sh [godot] [screenshot-dir]
set -euo pipefail
GODOT="${1:-godot}"
SHOTS="${2:-}"
cd "$(dirname "$0")/.."
DIR="$(mktemp -d)"
xvfb-run -a -s "-screen 0 1428x640x24" "$GODOT" --path . --rendering-driver opengl3 --resolution 1428x640 -- \
  --fresh --autostart --touch-ui --safe-inset=38,0 "--save-path=$DIR/save.json" --root-bot=res://tests/jam_story_bot.gd \
  ${SHOTS:+"--capture=$SHOTS"} 2>&1 | grep -E "^  (ok|FAIL)|JAM STORY|SCRIPT ERROR" || true
