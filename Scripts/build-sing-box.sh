#!/usr/bin/env bash
# Download sing-box release into ProxyHelper/dist for bundling.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/ProxyHelper/dist"
VERSION="${SING_BOX_VERSION:-1.12.12}"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64|aarch64) SING_ARCH="arm64" ;;
  x86_64) SING_ARCH="amd64" ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac

NAME="sing-box-${VERSION}-darwin-${SING_ARCH}"
URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/${NAME}.tar.gz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUT"
echo "Fetching $URL …"
curl -fsSL "$URL" -o "$TMP/sing-box.tgz"
tar -xzf "$TMP/sing-box.tgz" -C "$TMP"
BIN="$(find "$TMP" -type f -name sing-box | head -1)"
if [[ -z "$BIN" || ! -x "$BIN" ]]; then
  # tarball may not have +x
  BIN="$(find "$TMP" -type f -name sing-box | head -1)"
fi
if [[ -z "$BIN" ]]; then
  echo "sing-box binary missing from archive" >&2
  exit 1
fi
install -m 755 "$BIN" "$OUT/sing-box"
install -m 644 "$ROOT/ProxyHelper/local.checkpointvpn.proxy.plist" "$OUT/local.checkpointvpn.proxy.plist"
install -m 755 "$ROOT/Scripts/checkpoint-vpn-proxyctl.sh" "$OUT/checkpoint-vpn-proxyctl"
cat > "$OUT/BUILD_INFO.txt" <<EOF
sing-box $VERSION darwin-$SING_ARCH
downloaded $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
ls -la "$OUT"
echo "Staged sing-box in $OUT"
