#!/bin/bash
# Build a drag-and-drop DMG for GitHub Releases.
# Ad-hoc signed: no Developer ID / notarization. Gatekeeper will warn.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-1.0.0}"
VERSION="${VERSION#v}"
BUILD_DIR="$ROOT/build/DerivedData"
STAGING="$ROOT/build/dmg"
APP_NAME="CheckpointVPNOneClick.app"
APP="$BUILD_DIR/Build/Products/Release/$APP_NAME"
DMG="$ROOT/build/CheckpointVPNOneClick-${VERSION}.dmg"

cd "$ROOT"
mkdir -p "$ROOT/build"
touch "$ROOT/build/.metadata_never_index"
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi

xcodebuild \
  -project "$ROOT/CheckpointVPNOneClick.xcodeproj" \
  -scheme CheckpointVPNOneClick \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -destination "platform=macOS" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=NO \
  build

test -d "$APP"

codesign --force --sign - \
  --identifier "local.checkpointvpn.oneclick" \
  --entitlements "$ROOT/CheckpointVPNOneClick/CheckpointVPNOneClick.entitlements" \
  "$APP"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Checkpoint VPN" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG"

# ponytail: fail if hdiutil wrote an empty/corrupt image
test -s "$DMG"
hdiutil imageinfo "$DMG" >/dev/null

echo "Created $DMG"
