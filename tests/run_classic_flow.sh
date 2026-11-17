#!/usr/bin/env bash
# End-to-end check of the classic game through the real game, starting from a save written by the previous
# versions (contracts in progress): conversion, the cylinder picker, a bonus order by its one button, the delivery
# van, saving mid-trip, a restart, and two hours away.
# Usage: tests/run_classic_flow.sh [godot]
set -euo pipefail
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
DIR="$(mktemp -d)"
SAVE="$DIR/classic_save.json"
"$GODOT" --headless --path . -s tests/make_legacy_save.gd -- "--out=$SAVE" 2>&1 | grep -E "wrote|SCRIPT ERROR" || true
run() {
  local cmd=("$GODOT" --path . --rendering-driver opengl3 -- "--save-path=$SAVE" --root-bot=res://tests/classic_flow_bot.gd "--phase=$1")
  if [ -z "${DISPLAY:-}" ]; then cmd=(xvfb-run -a -s "-screen 0 1280x720x24" "${cmd[@]}"); fi
  "${cmd[@]}" 2>&1 | grep -E "^  (ok|FAIL)|CLASSIC FLOW|SCRIPT ERROR" || true
}
run 1
run 2
python3 - "$SAVE" <<'PY'
import json, sys, time
d = json.load(open(sys.argv[1]))
d["state"]["last_saved_unix"] = time.time() - 7200
json.dump(d, open(sys.argv[1], "w"))
print("  save version on disk:", d["version"])
PY
run 3
