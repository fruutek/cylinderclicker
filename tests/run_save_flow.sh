#!/usr/bin/env bash
# End-to-end save/load/offline check through the real game (headless).
# Usage: tests/run_save_flow.sh [path-to-godot]
set -euo pipefail
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
SAVE="$(mktemp -d)/flow_save.json"
ARGS=(--headless --path . -- "--save-path=$SAVE" --autostart --bot=res://tests/save_flow_bot.gd)
P1=$("$GODOT" "${ARGS[@]}" 2>/dev/null | grep PHASE1)
echo "$P1"
# Pretend the game was closed two hours ago.
python3 - "$SAVE" <<'PY'
import json, sys, time
p = sys.argv[1]
d = json.load(open(p))
d["state"]["last_saved_unix"] = time.time() - 7200
json.dump(d, open(p, "w"))
print("saved cash:", d["state"]["cash"], "version:", d["version"])
PY
P2=$("$GODOT" "${ARGS[@]}" 2>/dev/null | grep PHASE2)
echo "$P2"
python3 - "$P1" "$P2" <<'PY'
import re, sys
p1, p2 = sys.argv[1], sys.argv[2]
c1 = float(re.search(r"cash=([\d.]+)", p1).group(1))
c2 = float(re.search(r"cash=([\d.]+)", p2).group(1))
rate = float(re.search(r"rate=([\d.]+)", p2).group(1))
profit = float(re.search(r"profit=([\d.]+)", p2).group(1))
l1 = re.search(r"levels=(\{.*?\})", p1).group(1)
l2 = re.search(r"levels=(\{.*?\})", p2).group(1)
expected = int(rate * 7200) * profit
ok = l1 == l2 and "offline_dialog=true" in p2 and abs((c2 - c1) - expected) <= expected * 0.02 + 2 * profit
print("offline earnings: got %.2f, expected about %.2f" % (c2 - c1, expected))
print("SAVE FLOW: PASS" if ok else "SAVE FLOW: FAIL")
sys.exit(0 if ok else 1)
PY
