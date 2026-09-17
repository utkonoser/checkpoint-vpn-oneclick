#!/bin/bash
# Stable install so Accessibility TCC sticks across rebuilds.
# Ad-hoc DerivedData binaries get a new CDHash every build; macOS then
# treats them as a different app even if the toggle is still on.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUPPORT="$HOME/Library/Application Support/CheckpointVPNOneClick"
KEYCHAIN="$SUPPORT/codesign.keychain-db"
PASSWORD="checkpoint-vpn-local-codesign"
CERT_CN="CheckpointVPNOneClick Local"
INSTALL_DIR="$HOME/Applications"
INSTALL="$INSTALL_DIR/CheckpointVPNOneClick.app"
BUILD_DIR="$ROOT/build/DerivedData"
APP="$BUILD_DIR/Build/Products/Debug/CheckpointVPNOneClick.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$SUPPORT" "$INSTALL_DIR" "$ROOT/build"
touch "$ROOT/build/.metadata_never_index"

unlock_keychain() {
  security set-keychain-settings -t 86400 -u "$KEYCHAIN" >/dev/null 2>&1 || true
  security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
}

if [[ ! -f "$KEYCHAIN" ]]; then
  security create-keychain -p "$PASSWORD" "$KEYCHAIN"
fi
unlock_keychain

if ! security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "$CERT_CN"; then
  cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = req_distinguished_name
prompt = no
x509_extensions = v3_req
[req_distinguished_name]
CN = $CERT_CN
O = CheckpointVPNOneClick
[v3_req]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
  # Homebrew OpenSSL 3 writes a PKCS12 MAC that `security import` rejects.
  OPENSSL=/usr/bin/openssl
  "$OPENSSL" req -new -x509 -days 3650 -nodes \
    -newkey rsa:2048 \
    -keyout "$TMP/vpn.key" \
    -out "$TMP/vpn.crt" \
    -config "$TMP/cert.cnf"
  "$OPENSSL" pkcs12 -export \
    -inkey "$TMP/vpn.key" \
    -in "$TMP/vpn.crt" \
    -out "$TMP/vpn.p12" \
    -passout pass:vpnlocal \
    -name "$CERT_CN"
  security import "$TMP/vpn.p12" -k "$KEYCHAIN" -P vpnlocal -A \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
  # Trust this cert for code signing so find-identity marks it valid.
  security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/vpn.crt" >/dev/null 2>&1 || true
fi

unlock_keychain
echo "Signing identities in local keychain:"
security find-identity -v -p codesigning "$KEYCHAIN" || true

if command -v xcodegen >/dev/null 2>&1; then
  (cd "$ROOT" && xcodegen generate)
fi

xcodebuild \
  -project "$ROOT/CheckpointVPNOneClick.xcodeproj" \
  -scheme CheckpointVPNOneClick \
  -configuration Debug \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=NO \
  build

# codesign only searches keychains on the user search list.
if ! security list-keychains -d user | grep -Fq "codesign.keychain-db"; then
  current=()
  while IFS= read -r line; do
    current+=("${line//\"/}")
  done < <(security list-keychains -d user)
  security list-keychains -d user -s "$KEYCHAIN" "${current[@]}"
fi
unlock_keychain

IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk -F'"' '/CheckpointVPNOneClick Local/ {print $2; exit}')"
if [[ -n "$IDENTITY" ]]; then
  # Keep the designated requirement stable so TCC survives rebuilds.
  codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" \
    --identifier "local.checkpointvpn.oneclick" \
    --entitlements "$ROOT/CheckpointVPNOneClick/CheckpointVPNOneClick.entitlements" \
    "$APP"
else
  echo "warning: no valid local codesign identity; ad-hoc sign with a stable identifier" >&2
  codesign --force --sign - \
    --identifier "local.checkpointvpn.oneclick" \
    --entitlements "$ROOT/CheckpointVPNOneClick/CheckpointVPNOneClick.entitlements" \
    "$APP"
fi

codesign -dv --verbose=2 "$APP" || true

osascript -e 'tell application "Checkpoint VPN" to quit' >/dev/null 2>&1 || true
pkill -f "/CheckpointVPNOneClick.app/Contents/MacOS/CheckpointVPNOneClick" >/dev/null 2>&1 || true
sleep 0.4

rm -rf "$INSTALL"
ditto "$APP" "$INSTALL"
xattr -dr com.apple.quarantine "$INSTALL" 2>/dev/null || true

remove_extra_apps() {
  local keep="" lsreg
  keep="$(cd "$INSTALL" && pwd -P)"
  lsreg="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  local roots=("$HOME/Applications" /Applications "$ROOT/build")
  if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
    roots+=("$HOME/Library/Developer/Xcode/DerivedData")
  fi
  local app real
  while IFS= read -r app; do
    [[ -d "$app" ]] || continue
    real="$(cd "$app" && pwd -P)"
    [[ "$real" == "$keep" ]] && continue
    echo "Removing extra copy $app"
    "$lsreg" -u "$app" >/dev/null 2>&1 || true
    rm -rf "$app"
  done < <(find "${roots[@]}" -name 'CheckpointVPNOneClick.app' -type d -prune -print 2>/dev/null)
  "$lsreg" -f "$INSTALL" >/dev/null 2>&1 || true
}
remove_extra_apps

echo "Installed $INSTALL"
open "$INSTALL"
echo "Enable Checkpoint VPN in System Settings → Privacy & Security → Accessibility, then Quit from the menu bar and reopen ~/Applications/CheckpointVPNOneClick.app"
