#!/usr/bin/env bash
# End-to-end check of the menus, naming, pause, saving and restart.
# Usage: tests/run_menu_flow.sh [godot] [screenshot-dir]
# With a screenshot dir it runs under xvfb and captures each screen.
set -euo pipefail
GODOT="${1:-godot}"
SHOTS="${2:-}"
cd "$(dirname "$0")/.."
DIR="$(mktemp -d)"
SAVE="$DIR/flow_save.json"
run() {
  if [ -n "$SHOTS" ]; then
    xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-driver opengl3 --resolution 1280x720 -- \
      "--save-path=$SAVE" --root-bot=res://tests/menu_flow_bot.gd "--phase=$1" "--capture=$SHOTS" 2>&1
  else
    "$GODOT" --headless --path . -- "--save-path=$SAVE" --root-bot=res://tests/menu_flow_bot.gd "--phase=$1" 2>&1
  fi | grep -E "^  (ok|FAIL)|MENU FLOW|EXPECT|GOT|SCRIPT ERROR" || true
}
run 1
run 2
# Damage both the save and its backup, then make sure the menu copes.
echo "{ broken" > "$SAVE"
echo "{ broken" > "$SAVE.bak"
run 3
