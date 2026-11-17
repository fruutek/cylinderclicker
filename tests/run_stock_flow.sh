#!/usr/bin/env bash
# End-to-end check of the warehouse economy through the real game, starting from a save written by the
# previous release (version 4, contracts in progress): migration, the telephone, orders and lorries by
# button, saving in the middle of a shipment, a restart, and two hours away.
# Usage: tests/run_stock_flow.sh [godot]
set -euo pipefail
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
DIR="$(mktemp -d)"
SAVE="$DIR/stock_save.json"
"$GODOT" --headless --path . -s tests/make_legacy_save.gd -- "--out=$SAVE" 2>&1 | grep -E "wrote|SCRIPT ERROR" || true
run() {
  # Needs a window for the interface: use xvfb if there is no display.
  local cmd=("$GODOT" --path . --rendering-driver opengl3 -- "--save-path=$SAVE" --root-bot=res://tests/stock_flow_bot.gd "--phase=$1")
  if [ -z "${DISPLAY:-}" ]; then cmd=(xvfb-run -a -s "-screen 0 1280x720x24" "${cmd[@]}"); fi
  "${cmd[@]}" 2>&1 | grep -E "^  (ok|FAIL)|STOCK FLOW|EXPECT|SCRIPT ERROR" || true
}
run 1
run 2
# Pretend the game was closed two hours ago.
python3 - "$SAVE" <<'PY'
import json, sys, time
d = json.load(open(sys.argv[1]))
d["state"]["last_saved_unix"] = time.time() - 7200
json.dump(d, open(sys.argv[1], "w"))
print("  save version on disk:", d["version"], "- orders:", len(d["state"]["contracts"]["active"]), "open")
PY
run 3
