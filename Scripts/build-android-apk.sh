#!/usr/bin/env bash
# Build the current Android release APK (native snxcore + Gradle).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_DIR="$ROOT/android"
OUT_DIR="$ROOT/build"
OUT_APK="$OUT_DIR/CheckpointVPNOneClick.apk"

if [[ -z "${JAVA_HOME:-}" ]]; then
  if [[ -d /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home ]]; then
    export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
  elif command -v /usr/libexec/java_home >/dev/null 2>&1; then
    export JAVA_HOME="$(/usr/libexec/java_home 2>/dev/null || true)"
  fi
fi
if [[ -n "${JAVA_HOME:-}" ]]; then
  export PATH="$JAVA_HOME/bin:$PATH"
fi

# Prefer a real existing SDK. Stale ANDROID_HOME (common: ~/Library/Android/sdk missing)
# must not block the repo-local android/.sdk bootstrap.
pick_sdk() {
  local candidate
  for candidate in "$@"; do
    if [[ -n "$candidate" && -d "$candidate/platforms" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

SDK="$(pick_sdk \
  "${ANDROID_HOME:-}" \
  "${ANDROID_SDK_ROOT:-}" \
  "$ANDROID_DIR/.sdk" \
  "$HOME/Library/Android/sdk" \
)" || {
  echo "No Android SDK found. Tried ANDROID_HOME, ANDROID_SDK_ROOT, android/.sdk, ~/Library/Android/sdk" >&2
  echo "Bootstrap one into the repo with:" >&2
  echo "  ./Scripts/bootstrap-android-sdk.sh" >&2
  exit 1
}
export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"
echo "Using ANDROID_HOME=$ANDROID_HOME"

NDK_VERSION="${ANDROID_NDK_VERSION:-27.2.12479018}"
if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  if [[ -d "$ANDROID_HOME/ndk/$NDK_VERSION" ]]; then
    export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/$NDK_VERSION"
  else
    # pick newest installed NDK
    newest="$(ls -1 "$ANDROID_HOME/ndk" 2>/dev/null | sort -V | tail -1 || true)"
    if [[ -n "$newest" ]]; then
      export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/$newest"
    fi
  fi
fi

echo "sdk.dir=$ANDROID_HOME" > "$ANDROID_DIR/local.properties"

mkdir -p "$OUT_DIR"
cd "$ANDROID_DIR"
chmod +x gradlew

echo "==> assembleRelease (cargo-ndk via Gradle preBuild)"
./gradlew :app:assembleRelease --no-daemon

SRC="$(ls -1 app/build/outputs/apk/release/app-release.apk 2>/dev/null | head -1 || true)"
if [[ -z "$SRC" ]]; then
  echo "Release APK not found under android/app/build/outputs/apk/release/" >&2
  exit 1
fi

cp -f "$SRC" "$OUT_APK"
echo "APK: $OUT_APK"
ls -lh "$OUT_APK"
