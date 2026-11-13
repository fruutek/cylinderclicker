#!/usr/bin/env bash
# Runs the in-app Android test on a connected emulator/device via adb.
# Usage: tests/android/run_emulator_test.sh <test.apk> <output-dir>
# The test APK is the game plus tests/android_bot.gd (export preset "Android Test").
set -uo pipefail
APK="$1"
OUT="$2"
PKG="com.fruutek.cylinderclicker.test"
ACT="$PKG/com.godot.game.GodotAppLauncher"
mkdir -p "$OUT"
LOG="$OUT/godot.log"
: > "$LOG"

adb uninstall "$PKG" >/dev/null 2>&1 || true
adb install -r "$APK" || exit 1
adb shell wm size; adb shell wm density
adb logcat -c
adb logcat -v raw -s godot:V Godot:V >> "$LOG" &
LOGCAT_PID=$!
trap 'kill $LOGCAT_PID 2>/dev/null' EXIT

# Follows the app log until a line matching $1 appears (or $2 seconds pass),
# taking a device screenshot on "SHOT <name>" and sending real taps on "PROBE x y".
SEEN=0
follow() {
  local until="$1" limit="$2" start=$SECONDS
  while [ $((SECONDS - start)) -lt "$limit" ]; do
    local total; total=$(wc -l < "$LOG")
    if [ "$total" -gt "$SEEN" ]; then
      while IFS= read -r line; do
        SEEN=$((SEEN + 1))
        case "$line" in
          SHOT\ *) adb exec-out screencap -p > "$OUT/${line#SHOT }.png" ;;
          PROBE\ *) set -- $line; echo "sending 20 real taps at $2,$3"
                    for i in $(seq 1 20); do adb shell input tap "$2" "$3"; done ;;
        esac
        case "$line" in *"$until"*) return 0 ;; esac
      done < <(tail -n +"$((SEEN + 1))" "$LOG")
    fi
    sleep 0.3
  done
  echo "TIMEOUT waiting for: $until"
  return 1
}

adb shell am start -n "$ACT"
follow "PHASE DONE" 420; P1=$?
adb exec-out screencap -p > "$OUT/a17_before_home.png"
# Send the app to the background the way a player would, then kill it.
adb shell input keyevent KEYCODE_HOME
sleep 4
adb exec-out screencap -p > "$OUT/a18_home_screen.png"
adb shell am force-stop "$PKG"
sleep 1

adb shell am start -n "$ACT"
follow "BG READY" 240; P2=$?
adb shell input keyevent KEYCODE_HOME
sleep 6
adb shell am start -n "$ACT"
follow "ANDROID TEST DONE" 120; P3=$?

kill $LOGCAT_PID 2>/dev/null
echo "=================== app log ==================="
grep -E "^  (ok|FAIL|viewport|rapid|keyboard)|ANDROID INFO|TOUCH FLOW|EXPECT|SCRIPT ERROR|ERROR|PROBE" "$LOG" | head -200
adb shell dumpsys window displays 2>/dev/null | grep -E "cur=|rotation" | head -5
FAILS=$(grep -c "^  FAIL" "$LOG")
PASSES=$(grep -c "TOUCH FLOW PHASE [12]: PASS" "$LOG")
ERRORS=$(grep -c "SCRIPT ERROR" "$LOG")
echo "phases passed: $PASSES/2, failed checks: $FAILS, script errors: $ERRORS, follow results: $P1 $P2 $P3"
[ "$PASSES" = 2 ] && [ "$FAILS" = 0 ] && [ "$ERRORS" = 0 ]
