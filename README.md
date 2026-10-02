# Checkpoint VPN One-Click

Menu bar app for **Check Point** remote access on macOS. It ships its own tunnel helper (vendored [snx-rs](https://github.com/ancwrd1/snx-rs) AGPL fork) and drives it with a saved password + live TOTP — no official Check Point UI, no separate `SNX-RS.pkg`.

**Work VPN only (split-tunnel):** corporate routes come from the gateway; the default internet route stays free for [Karing](https://karing.app) (or similar).

Not affiliated with Check Point.

## Features

- **Connect / Disconnect** via bundled `CheckpointVPNTunnel` + `checkpoint-vpnctl`
- **Embedded helper**: first Connect (or **Install / repair tunnel helper…**) installs LaunchDaemon `local.checkpointvpn.tunnel` (admin password once)
- **Split-tunnel** (`default-route=false`) — keeps Office Mode / GW routes, does not own all traffic
- **Per-site secrets**: password + TOTP (Base32, `otpauth://`, or QR); clear fields with Saved / Not set status
- **Live TOTP** preview in Settings
- **Site picker** in the menu bar
- **Work domains** + **Copy Karing rules** for Direct diversion
- **Ignore server certificate** toggle (common on corporate gateways)
- **Restart / repair** tunnel helper after sleep

Secrets live in `~/Library/Application Support/CheckpointVPNOneClick/secrets.plist` (mode `0600`), not in the login Keychain.

## Download

- [Latest release](https://github.com/utkonoser/checkpoint-vpn-oneclick/releases/latest)

Builds are **ad-hoc signed** (no Apple Developer ID). After drag-and-drop to `/Applications`, right-click → **Open**, or:

```bash
xattr -dr com.apple.quarantine /Applications/CheckpointVPNOneClick.app
```

## Requirements

| Need | Notes |
|------|--------|
| macOS 14+ | |
| Admin once | Installs `/Library/Application Support/CheckpointVPNTunnel` + LaunchDaemon |
| Optional Karing | Non-corporate traffic / proxy |
| From source | Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Rust (`cargo`) for the helper |

**Conflicts:** disconnect the official Check Point Endpoint client and upstream snx-rs (`com.github.snx-rs`) before connecting — two IPsec stacks fight over routes.

## Quick setup

1. Install / open the app (`~/Applications` or `/Applications`).
2. **Settings → VPN:** site (hostname), username, login type (usually `vpn_VPN_RA`).
3. **Settings → Secrets:** enter password and TOTP (or import QR), then **Save secrets**. Status shows **Saved** / **Not set**.
4. Optional: **Work domains** (one per line) → **Copy Karing rules**.
5. **Install / repair tunnel helper…** (or Connect — install runs when needed).
6. **Connect** from the menu bar or Settings.

Discover login types after the helper is installed:

```bash
/Library/Application\ Support/CheckpointVPNTunnel/CheckpointVPNTunnel -m info -s vpn.example.com
```

## Using with Karing

Goal: work nets → this app’s tunnel; everything else → Karing; RF / work domains → **Direct** in Karing so they hit macOS routes → utun.

1. Install [Karing](https://karing.app), add subscription, enable TUN / system proxy as required.
2. **Diversion → Country / Region:** Russia (or yours) so geoip RF → **Direct**.
3. Custom diversion group (e.g. `work-vpn`): paste Domain Suffixes from **Copy Karing rules** → action **Direct**.
4. Start **Karing** first, then **Connect** here.

If corp sites still go through the proxy, check Karing hit detection / rule order. If random internet goes into the work tunnel, confirm split-tunnel (`default-route=false` — set automatically).

```text
Browser / apps
    ├─ work domain (Karing Direct) ──► macOS routes ──► CheckpointVPNTunnel (GW CIDRs)
    ├─ RF IP (geoip Direct)        ──► macOS routes
    └─ rest                        ──► Karing node
```

## Architecture (short)

| Piece | Role |
|-------|------|
| Swift menu bar app | UI, secrets, TOTP, connect conf |
| `CheckpointVPNTunnel` | Root daemon (snx-rs command mode fork) |
| Socket | `/var/run/checkpoint-vpn.sock` |
| LaunchDaemon | `local.checkpointvpn.tunnel` |

Details: [docs/tunnel-engine.md](docs/tunnel-engine.md). Licensing / AGPL: [THIRD_PARTY.md](THIRD_PARTY.md). Manual checks: [docs/manual-test-plan.md](docs/manual-test-plan.md).

## Build from source

```bash
make helper    # Vendor/snx-rs → TunnelHelper/dist
make install   # sign, embed helper, install to ~/Applications
```

```bash
make build
make test
make generate  # xcodegen → .xcodeproj
make dmg       # local DMG under build/
```

GitHub release DMG: **Actions → Release DMG → Run workflow** (needs Rust on the runner; embeds the helper).

### After sleep / helper issues

Settings → **Restart tunnel helper…** or **Install / repair…**. Equivalent:

```bash
sudo launchctl kickstart -k system/local.checkpointvpn.tunnel
```
