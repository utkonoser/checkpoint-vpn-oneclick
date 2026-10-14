#!/usr/bin/env bash
# Install sing-box personal proxy LaunchDaemon from app bundle payload.
# Intended to run via osascript "with administrator privileges".
set -euo pipefail

SRC="${1:-}"
if [[ -z "$SRC" || ! -d "$SRC" ]]; then
  echo "usage: $0 /path/to/ProxyHelperPayloadDir" >&2
  exit 1
fi

BIN_SRC="$SRC/sing-box"
CTL_SRC="$SRC/checkpoint-vpn-proxyctl"
PLIST_SRC="$SRC/local.checkpointvpn.proxy.plist"

for f in "$BIN_SRC" "$CTL_SRC" "$PLIST_SRC"; do
  if [[ ! -f "$f" ]]; then
    echo "missing $f" >&2
    exit 1
  fi
done

SUPPORT="/Library/Application Support/CheckpointVPNProxy"
PLIST_DST="/Library/LaunchDaemons/local.checkpointvpn.proxy.plist"
LABEL="system/local.checkpointvpn.proxy"

/bin/launchctl bootout "$LABEL" 2>/dev/null || true
/usr/bin/killall sing-box 2>/dev/null || true

/bin/mkdir -p "$SUPPORT"
/usr/bin/install -m 755 "$BIN_SRC" "$SUPPORT/sing-box"
/usr/bin/install -m 755 "$CTL_SRC" "$SUPPORT/checkpoint-vpn-proxyctl"
/usr/bin/install -m 644 "$PLIST_SRC" "$SUPPORT/local.checkpointvpn.proxy.plist"
/usr/bin/install -m 644 "$PLIST_SRC" "$PLIST_DST"

# Placeholder config so a later start has a file to read.
if [[ ! -f "$SUPPORT/sing-box.json" ]]; then
  /bin/cat > "$SUPPORT/sing-box.json" <<'EOF'
{"log":{"level":"info"},"inbounds":[],"outbounds":[{"type":"direct","tag":"direct"}]}
EOF
  /bin/chmod 644 "$SUPPORT/sing-box.json"
fi

/bin/launchctl bootstrap system "$PLIST_DST" 2>/dev/null \
  || /bin/launchctl load -w "$PLIST_DST"
/bin/launchctl kickstart -k "$LABEL" 2>/dev/null \
  || /bin/launchctl kickstart "$LABEL" 2>/dev/null \
  || true

echo "Installed CheckpointVPNProxy ($LABEL)"
