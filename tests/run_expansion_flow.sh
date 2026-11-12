#!/usr/bin/env bash
# End-to-end check of the stainless expansion through the real game,
# starting from a save file written by the previous single-factory version.
# Usage: tests/run_expansion_flow.sh [godot]
set -euo pipefail
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
DIR="$(mktemp -d)"
SAVE="$DIR/flow_save.json"
# A version-2 (copper only) save, exactly as the last release wrote it.
python3 - "$SAVE" <<'PY'
import json, sys, time
levels = {"machine_cut": 12, "machine_roll": 12, "machine_weld": 12, "machine_test": 12, "machine_foam": 12,
          "machine_pack": 12, "finish": 4, "hand_tools": 3, "conveyor": 2}
state = {"factory_name": "Taylor & Sons", "cash": 2000000.0, "lifetime_earned": 2700000.0, "cylinders_made": 5200.0,
         "total_clicks": 900, "play_seconds": 2400.0, "upgrade_levels": levels, "unlocked_products": ["copper", "standard"],
         "current_product": {"material": "copper", "range": "standard", "variants": []}, "tutorial_step": 7,
         "best_rate_per_min": 180.0, "last_saved_unix": time.time(),
         "settings": {"sfx_volume": 0.8, "music_volume": 0.4, "fullscreen": False},
         "line": {"stations": [{"progress": 0.0}] * 6, "belts": [[], [], [], [], [], []]}}
json.dump({"game": "cylinder_clicker", "version": 2, "state": state}, open(sys.argv[1], "w"))
PY
run() {
  "$GODOT" --headless --path . -- "--save-path=$SAVE" --root-bot=res://tests/expansion_flow_bot.gd "--phase=$1" 2>&1 \
    | grep -E "^  (ok|FAIL)|EXPANSION FLOW|EXPECT|SCRIPT ERROR" || true
}
run 1
run 2
# Pretend the game was closed two hours ago.
python3 - "$SAVE" <<'PY'
import json, sys, time
d = json.load(open(sys.argv[1]))
d["state"]["last_saved_unix"] = time.time() - 7200
json.dump(d, open(sys.argv[1], "w"))
print("  save version on disk:", d["version"], "- factories:", ", ".join(d["state"]["factories"].keys()))
PY
run 3
