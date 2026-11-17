#!/usr/bin/env bash
# CI helper: points Godot at the runner's Android SDK and Java, and prepares
# the signing key. With the repository secrets ANDROID_KEYSTORE_BASE64 and
# ANDROID_KEYSTORE_PASSWORD set, builds are signed with your permanent key.
# Without them the shared test key committed in this folder is used (stable across builds, but not private).
set -euo pipefail
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"
JAVA="${JAVA_HOME_17_X64:-${JAVA_HOME:-}}"
mkdir -p "$HOME/.config/godot"
cat > "$HOME/.config/godot/editor_settings-4.7.tres" <<TRES
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/java_sdk_path = "$JAVA"
export/android/android_sdk_path = "$SDK"
TRES
KEYSTORE="$RUNNER_TEMP/release.keystore"
if [ -n "${ANDROID_KEYSTORE_BASE64:-}" ] && [ -n "${ANDROID_KEYSTORE_PASSWORD:-}" ]; then
  echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > "$KEYSTORE"
  PASSWORD="$ANDROID_KEYSTORE_PASSWORD"
  ALIAS="${ANDROID_KEY_ALIAS:-cylinderclicker}"
  echo "signing=release" >> "$GITHUB_OUTPUT"
  echo "Using the permanent signing key from repository secrets."
else
  # No signing secrets: use the shared test key that is committed to the repository. It is one fixed key (not
  # a secret: anyone can read it), so every build signed with it can update the previous one in place. It is fine
  # for a hobby game and for testing; a store release needs a private key supplied through the secrets above.
  KEYSTORE="$(pwd)/tools/ci/cylinderclicker-shared-test.keystore"
  PASSWORD="cylinderclicker-test"
  ALIAS="cylinderclicker-test"
  echo "signing=testkey" >> "$GITHUB_OUTPUT"
  echo "::warning::No signing secrets set - this build is signed with the shared test key (stable, but not private)."
fi
{
  echo "GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$KEYSTORE"
  echo "GODOT_ANDROID_KEYSTORE_RELEASE_USER=$ALIAS"
  echo "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=$PASSWORD"
} >> "$GITHUB_ENV"
