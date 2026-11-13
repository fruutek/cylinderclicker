#!/usr/bin/env bash
# CI helper: installs the Godot editor and the export templates named as
# arguments (file names inside the official templates archive).
# Usage: tools/ci/install_godot.sh windows_release_x86_64.exe android_release.apk ...
set -euo pipefail
VERSION="${GODOT_VERSION:-4.7.2-stable}"
BASE="https://github.com/godotengine/godot/releases/download/${VERSION}"
curl -sSL -o /tmp/godot.zip "${BASE}/Godot_v${VERSION}_linux.x86_64.zip"
unzip -q -o /tmp/godot.zip -d /tmp
sudo mv "/tmp/Godot_v${VERSION}_linux.x86_64" /usr/local/bin/godot
if [ "$#" -gt 0 ]; then
  curl -sSL -o /tmp/templates.tpz "${BASE}/Godot_v${VERSION}_export_templates.tpz"
  DIR="$HOME/.local/share/godot/export_templates/${VERSION/-/.}"
  mkdir -p "$DIR"
  FILES=("templates/version.txt")
  for f in "$@"; do FILES+=("templates/$f"); done
  unzip -q -j -o /tmp/templates.tpz "${FILES[@]}" -d "$DIR"
  rm /tmp/templates.tpz
fi
rm /tmp/godot.zip
godot --version
