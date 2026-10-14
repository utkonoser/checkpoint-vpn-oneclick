#!/usr/bin/env bash
# Copy built proxy helper into an .app bundle Resources/ProxyHelper/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/ProxyHelper/dist"
APP="${1:-}"

if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "usage: $0 /path/to/CheckpointVPNOneClick.app" >&2
  exit 1
fi

if [[ ! -x "$DIST/sing-box" ]]; then
  echo "Missing $DIST/sing-box — run Scripts/build-sing-box.sh first." >&2
  exit 1
fi

DEST="$APP/Contents/Resources/ProxyHelper"
mkdir -p "$DEST"
install -m 755 "$DIST/sing-box" "$DEST/sing-box"
install -m 755 "$DIST/checkpoint-vpn-proxyctl" "$DEST/checkpoint-vpn-proxyctl"
install -m 644 "$DIST/local.checkpointvpn.proxy.plist" "$DEST/local.checkpointvpn.proxy.plist"
install -m 755 "$ROOT/Scripts/install-proxy-helper.sh" "$APP/Contents/Resources/install-proxy-helper.sh"
if [[ -f "$DIST/BUILD_INFO.txt" ]]; then
  install -m 644 "$DIST/BUILD_INFO.txt" "$DEST/BUILD_INFO.txt"
fi
echo "Bundled proxy helper into $DEST"
