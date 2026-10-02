#!/usr/bin/env bash
# Copy built tunnel helper into an .app bundle Resources/TunnelHelper/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/TunnelHelper/dist"
APP="${1:-}"

if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "usage: $0 /path/to/CheckpointVPNOneClick.app" >&2
  exit 1
fi

if [[ ! -x "$DIST/CheckpointVPNTunnel" || ! -x "$DIST/checkpoint-vpnctl" ]]; then
  echo "Missing $DIST binaries — run Scripts/build-tunnel-helper.sh first." >&2
  exit 1
fi

DEST="$APP/Contents/Resources/TunnelHelper"
mkdir -p "$DEST"
install -m 755 "$DIST/CheckpointVPNTunnel" "$DEST/CheckpointVPNTunnel"
install -m 755 "$DIST/checkpoint-vpnctl" "$DEST/checkpoint-vpnctl"
install -m 644 "$DIST/local.checkpointvpn.tunnel.plist" "$DEST/local.checkpointvpn.tunnel.plist"
install -m 755 "$ROOT/Scripts/install-tunnel-helper.sh" "$APP/Contents/Resources/install-tunnel-helper.sh"
if [[ -f "$DIST/BUILD_INFO.txt" ]]; then
  install -m 644 "$DIST/BUILD_INFO.txt" "$DEST/BUILD_INFO.txt"
fi
echo "Bundled tunnel helper into $DEST"
