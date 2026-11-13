#!/usr/bin/env bash
# CI helper: points Godot at the runner's Android SDK and Java, and prepares
# the signing key. With the repository secrets ANDROID_KEYSTORE_BASE64 and
# ANDROID_KEYSTORE_PASSWORD set, builds are signed with your permanent key.
# Without them a throw-away key is generated (fine for testing, but such an
# APK cannot update an installed copy signed with a different key).
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
  PASSWORD="temporary-ci-key"
  ALIAS="temporary"
  keytool -genkeypair -keystore "$KEYSTORE" -storetype PKCS12 -alias "$ALIAS" -keyalg RSA -keysize 2048 \
    -validity 365 -storepass "$PASSWORD" -keypass "$PASSWORD" -dname "CN=Cylinder Clicker CI test key" >/dev/null 2>&1
  echo "signing=testkey" >> "$GITHUB_OUTPUT"
  echo "::warning::No signing secrets set - this build is signed with a throw-away test key."
fi
{
  echo "GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$KEYSTORE"
  echo "GODOT_ANDROID_KEYSTORE_RELEASE_USER=$ALIAS"
  echo "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=$PASSWORD"
} >> "$GITHUB_ENV"
