#!/usr/bin/env bash
# Build vendored snx-rs into CheckpointVPNTunnel + checkpoint-vpnctl and stage into
# TunnelHelper/dist for bundling into the macOS app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor/snx-rs"
OUT="$ROOT/TunnelHelper/dist"
# Force a stable in-repo target dir (Cursor sandbox may otherwise redirect CARGO_TARGET_DIR).
TARGET_DIR="$ROOT/build/snx-rs-target"
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  arm64) DEFAULT_TARGET="aarch64-apple-darwin" ;;
  x86_64) DEFAULT_TARGET="x86_64-apple-darwin" ;;
  *) DEFAULT_TARGET="${HOST_ARCH}-apple-darwin" ;;
esac
TARGET="${TUNNEL_TARGET:-$DEFAULT_TARGET}"
PROFILE="${TUNNEL_PROFILE:-release}"

if [[ ! -f "$VENDOR/Cargo.toml" ]]; then
  echo "Missing $VENDOR — clone snx-rs into Vendor/snx-rs first." >&2
  exit 1
fi

command -v cargo >/dev/null || { echo "cargo/rustc required to build the tunnel helper" >&2; exit 1; }
rustup target add "$TARGET" >/dev/null

mkdir -p "$ROOT/build" "$OUT" "$TARGET_DIR"
export CARGO_TARGET_DIR="$TARGET_DIR"

echo "Building snx-rs + snxctl ($TARGET, profile=$PROFILE, CARGO_TARGET_DIR=$TARGET_DIR)…"
(
  cd "$VENDOR"
  cargo build --target="$TARGET" --profile="$PROFILE" \
    -p snx-rs -p snxctl \
    --features snxcore/vendored-openssl
)

BIN_DIR="$TARGET_DIR/$TARGET/$PROFILE"
if [[ ! -x "$BIN_DIR/snx-rs" ]]; then
  BIN_DIR="$TARGET_DIR/$PROFILE"
fi
if [[ ! -x "$BIN_DIR/snx-rs" || ! -x "$BIN_DIR/snxctl" ]]; then
  echo "Build finished but binaries not found under $TARGET_DIR" >&2
  find "$TARGET_DIR" -maxdepth 5 -type f \( -name snx-rs -o -name snxctl \) 2>/dev/null || true
  exit 1
fi

install -m 755 "$BIN_DIR/snx-rs" "$OUT/CheckpointVPNTunnel"
install -m 755 "$BIN_DIR/snxctl" "$OUT/checkpoint-vpnctl"
install -m 644 "$ROOT/TunnelHelper/local.checkpointvpn.tunnel.plist" "$OUT/local.checkpointvpn.tunnel.plist"

{
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "target=$TARGET"
  echo "profile=$PROFILE"
  echo "bin_dir=$BIN_DIR"
  if [[ -d "$VENDOR/.git" ]]; then
    echo "snx_rs_commit=$(git -C "$VENDOR" rev-parse HEAD 2>/dev/null || true)"
  elif [[ -f "$ROOT/Vendor/snx-rs.COMMIT" ]]; then
    echo "snx_rs_commit=$(cat "$ROOT/Vendor/snx-rs.COMMIT")"
  fi
  echo "socket=/var/run/checkpoint-vpn.sock"
  echo "launchd=local.checkpointvpn.tunnel"
} >"$OUT/BUILD_INFO.txt"

echo "Staged helper binaries in $OUT"
ls -la "$OUT"
