#!/usr/bin/env bash
# End-to-end check of trade contracts through the real game, starting from a
# save file written by the previous release (version 3, no contracts at all):
# play and dispatch, restart in the middle of a dispatch, then two hours away.
# Usage: tests/run_contracts_flow.sh [godot]
set -euo pipefail
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
DIR="$(mktemp -d)"
SAVE="$DIR/contracts_save.json"
# A version-3 save exactly as v0.4.0 wrote it: both factories, automated, no contract data.
python3 - "$SAVE" <<'PY'
import json, sys, time
copper = {"unlocked": True, "cylinders_made": 5200.0, "earned": 90000.0, "best_rate_per_min": 180.0, "line": {},
          "upgrade_levels": {"machine_cut": 10, "machine_roll": 10, "machine_weld": 10, "machine_test": 10, "machine_foam": 10,
                             "machine_pack": 10, "finish": 2, "hand_tools": 3}}
steel = {"unlocked": True, "cylinders_made": 40.0, "earned": 80000.0, "best_rate_per_min": 4.0, "line": {},
         "upgrade_levels": {m: 3 for m in ["machine_prep", "machine_laser", "machine_form", "machine_tig", "machine_coil", "machine_qa", "machine_case", "machine_ship"]}}
state = {"factory_name": "Contract Flow Ltd", "cash": 5000.0, "lifetime_earned": 170000.0, "total_clicks": 900, "play_seconds": 2400.0,
         "unlocked_products": ["copper", "standard", "stainless"], "factories": {"copper": copper, "stainless": steel},
         "current_factory": "copper", "tutorial_step": 7, "last_saved_unix": time.time(),
         "settings": {"sfx_volume": 0.8, "music_volume": 0.4, "fullscreen": False}}
json.dump({"game": "cylinder_clicker", "version": 3, "state": state}, open(sys.argv[1], "w"))
PY
run() {
  # Needs a window for the interface: use xvfb if there is no display.
  local cmd=("$GODOT" --path . --rendering-driver opengl3 -- --direct-sales "--save-path=$SAVE" --root-bot=res://tests/contracts_flow_bot.gd "--phase=$1")
  if [ -z "${DISPLAY:-}" ]; then cmd=(xvfb-run -a -s "-screen 0 1280x720x24" "${cmd[@]}"); fi
  "${cmd[@]}" 2>&1 | grep -E "^  (ok|FAIL)|CONTRACTS FLOW|EXPECT|SCRIPT ERROR" || true
}
run 1
run 2
# Pretend the game was closed two hours ago.
python3 - "$SAVE" <<'PY'
import json, sys, time
d = json.load(open(sys.argv[1]))
d["state"]["last_saved_unix"] = time.time() - 7200
json.dump(d, open(sys.argv[1], "w"))
print("  save version on disk:", d["version"], "- contracts:", len(d["state"]["contracts"]["active"]), "active")
PY
run 3
