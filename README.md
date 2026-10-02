# Checkpoint VPN One-Click

Menu bar app for **Check Point** remote access on macOS. It ships its own tunnel helper (vendored [snx-rs](https://github.com/ancwrd1/snx-rs) AGPL fork) and connects with a saved password + live TOTP — no official Check Point UI, no separate `SNX-RS.pkg`.

**Split-tunnel by default** (`default-route=false`): the VPN does not take the whole internet. Optionally list **CIDRs / IPs / hostnames** so only those destinations go through the tunnel.

Not affiliated with Check Point.

## Features

- **Menu bar**: status, Gateway switcher, Connect or Disconnect, Settings
- **Embedded helper**: first Connect installs LaunchDaemon `local.checkpointvpn.tunnel` (admin once); **Repair helper…** in Settings if needed
- **Multiple gateways**: type a hostname, save with **+**, switch via recent menu, remove with **−**
- **Split tunnel**: optional CIDR / IP / hostname list → `no-routing` + `add-routes` (hostnames resolve at Connect)
- **Gateway routes** when the list is empty (Office Mode from the gateway, still no default route)
- **Per-site secrets**: password + TOTP (Base32, `otpauth://`, or QR)
- **Live TOTP** in Settings
- **Ignore server certificate** (common on corporate gateways)

Secrets live in `~/Library/Application Support/CheckpointVPNOneClick/secrets.plist` (mode `0600`).

## Download

- [Latest release](https://github.com/utkonoser/checkpoint-vpn-oneclick/releases/latest)

Builds are **ad-hoc signed** (no Apple Developer ID). After installing, right-click → **Open**, or:

```bash
xattr -dr com.apple.quarantine /Applications/CheckpointVPNOneClick.app
```

## Requirements

| Need | Notes |
|------|--------|
| macOS 14+ | |
| Admin once | Installs `/Library/Application Support/CheckpointVPNTunnel` + LaunchDaemon |
| From source | Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Rust (`cargo`) for the helper |

**Conflicts:** disconnect the official Check Point Endpoint client and upstream snx-rs (`com.github.snx-rs`) before connecting — two IPsec stacks fight over routes.

## Quick setup

1. Install / open the app (`~/Applications` or `/Applications`).
2. **Settings → Account:** gateway hostname (**+** to save), username, login type (usually `vpn_VPN_RA`).
3. **Settings → Authentication:** password and TOTP (or import QR), then **Save**.
4. Optional **Split tunnel** — one destination per line:

   ```text
   10.0.0.0/8
   172.16.0.0/12
   intranet.example.com
   ```

5. **Connect** from the menu bar or Settings (helper install runs automatically when needed).

Discover login types after the helper is installed:

```bash
/Library/Application\ Support/CheckpointVPNTunnel/CheckpointVPNTunnel -m info -s vpn.example.com
```

### Split tunnel behavior

| List | Tunnel routing |
|------|----------------|
| Empty | Gateway Office Mode routes; `default-route=false` |
| Non-empty | `no-routing=true` + `add-routes=` resolved CIDRs only |

Hostnames resolve to IPv4 `/32` at Connect (DNS must work before the tunnel is up, or use CIDRs).

### Menu bar

```text
Idle — vpn.example.com
────────
Gateway ▸
Connect          # or Disconnect when connected
────────
Settings…
────────
Quit
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

Settings → Session → **Repair helper…**, or:

```bash
sudo launchctl kickstart -k system/local.checkpointvpn.tunnel
```
