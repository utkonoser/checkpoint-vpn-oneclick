#!/usr/bin/env bash
# Install CheckpointVPNTunnel LaunchDaemon from an app bundle (or TunnelHelper/dist).
# Intended to run via osascript "with administrator privileges".
set -euo pipefail

SRC="${1:-}"
if [[ -z "$SRC" || ! -d "$SRC" ]]; then
  echo "usage: $0 /path/to/HelperPayloadDir" >&2
  exit 1
fi

BIN_SRC="$SRC/CheckpointVPNTunnel"
CTL_SRC="$SRC/checkpoint-vpnctl"
PLIST_SRC="$SRC/local.checkpointvpn.tunnel.plist"

for f in "$BIN_SRC" "$CTL_SRC" "$PLIST_SRC"; do
  if [[ ! -f "$f" ]]; then
    echo "missing $f" >&2
    exit 1
  fi
done

SUPPORT="/Library/Application Support/CheckpointVPNTunnel"
PLIST_DST="/Library/LaunchDaemons/local.checkpointvpn.tunnel.plist"
LABEL="system/local.checkpointvpn.tunnel"

/bin/launchctl bootout "$LABEL" 2>/dev/null || true
/usr/bin/killall CheckpointVPNTunnel 2>/dev/null || true

/bin/mkdir -p "$SUPPORT"
/usr/bin/install -m 755 "$BIN_SRC" "$SUPPORT/CheckpointVPNTunnel"
/usr/bin/install -m 755 "$CTL_SRC" "$SUPPORT/checkpoint-vpnctl"
# Keep a copy of the plist next to binaries for repair/reinstall.
/usr/bin/install -m 644 "$PLIST_SRC" "$SUPPORT/local.checkpointvpn.tunnel.plist"
/usr/bin/install -m 644 "$PLIST_SRC" "$PLIST_DST"

/bin/launchctl bootstrap system "$PLIST_DST" 2>/dev/null \
  || /bin/launchctl load -w "$PLIST_DST"
/bin/launchctl kickstart -k "$LABEL" 2>/dev/null \
  || /bin/launchctl kickstart "$LABEL" 2>/dev/null \
  || true

# Symlink CLI for convenience (optional; app prefers bundled path).
/bin/mkdir -p /usr/local/bin
/bin/ln -sf "$SUPPORT/checkpoint-vpnctl" /usr/local/bin/checkpoint-vpnctl

echo "Installed CheckpointVPNTunnel ($LABEL)"
