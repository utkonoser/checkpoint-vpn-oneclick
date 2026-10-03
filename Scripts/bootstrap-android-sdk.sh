#!/usr/bin/env bash
# Install a minimal Android SDK+NDK into android/.sdk for local APK builds.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK_ROOT="${1:-$ROOT/android/.sdk}"
NDK_VERSION="${ANDROID_NDK_VERSION:-27.2.12479018}"

if [[ -z "${JAVA_HOME:-}" ]]; then
  if [[ -d /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home ]]; then
    export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
  fi
fi
if [[ -n "${JAVA_HOME:-}" ]]; then
  export PATH="$JAVA_HOME/bin:$PATH"
fi

mkdir -p "$SDK_ROOT/cmdline-tools"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ZIP="$TMP/cmdline-tools.zip"
if [[ ! -f /tmp/cmdline-tools-mac.zip ]]; then
  curl -fsSL -o /tmp/cmdline-tools-mac.zip \
    https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip
fi
cp /tmp/cmdline-tools-mac.zip "$ZIP"
unzip -q "$ZIP" -d "$TMP/extract"
rm -rf "$SDK_ROOT/cmdline-tools/latest"
mkdir -p "$SDK_ROOT/cmdline-tools/latest"
cp -R "$TMP/extract/cmdline-tools/"* "$SDK_ROOT/cmdline-tools/latest/"

yes | "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK_ROOT" \
  "platform-tools" \
  "platforms;android-35" \
  "build-tools;35.0.0" \
  "ndk;$NDK_VERSION"

echo "SDK ready: $SDK_ROOT"
echo "NDK: $SDK_ROOT/ndk/$NDK_VERSION"
