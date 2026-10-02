# Checkpoint VPN One-Click

Menu bar helper that connects **Check Point** VPN using an embedded tunnel engine (vendored [snx-rs](https://github.com/ancwrd1/snx-rs) AGPL fork) with a saved password + fresh TOTP.

No separate `SNX-RS.pkg` is required. On first Connect (or **Install / repair tunnel helper**), macOS asks for an admin password once to install `local.checkpointvpn.tunnel`.

Use this app for **work VPN only** (split-tunnel). For the rest of the internet, run [Karing](https://karing.app) (or similar) with Direct rules for work domains / RF IPs.

## Features

- **Connect / Disconnect** through the bundled `CheckpointVPNTunnel` helper
- **Split-tunnel by default**: `default-route=false` — keeps gateway-pushed corporate routes
- **Per-site secrets**: password + TOTP (Base32, `otpauth://`, or QR)
- **Site picker** in the menu bar
- **Work domains** list + **Copy Karing rules** for Direct diversion
- **One install**: app embeds the helper; LaunchDaemon install is in-app

Secrets are stored in `~/Library/Application Support/CheckpointVPNOneClick/secrets.plist` (mode `0600`).

## Download

- [Latest release](https://github.com/utkonoser/checkpoint-vpn-oneclick/releases/latest)

The GitHub build is ad-hoc signed (no Apple Developer ID). Drag the app to `/Applications`, then right-click → **Open** the first time, or run:

```bash
xattr -dr com.apple.quarantine /Applications/CheckpointVPNOneClick.app
```

## Requirements

- macOS 14+
- Admin password once (install LaunchDaemon)
- Optional: [Karing](https://karing.app) for non-corporate traffic
- Build from source also needs Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and a Rust toolchain (`cargo`) for the helper

If the official Check Point Endpoint Security client **or** upstream snx-rs (`com.github.snx-rs`) is installed, **disconnect it** before connecting here.

## Setup (work VPN)

1. Open the app from `~/Applications` or `/Applications`.
2. **Settings**: site (VPN hostname), username, login type (`vpn_VPN_RA` from helper info / gateway docs), password + TOTP.
3. Optional: work domains for Karing export.
4. **Install / repair tunnel helper…** (or just **Connect** — install runs automatically when needed).
5. Connect from the menu bar or Settings.

Login type discovery (optional):

```bash
/Library/Application\ Support/CheckpointVPNTunnel/CheckpointVPNTunnel -m info -s vpn.example.com
```

## Using with Karing (both at once)

1. Install [Karing](https://karing.app) and add your subscription / nodes.
2. Enable TUN / system proxy as required.
3. **Diversion → Country / Region:** Russia (or yours) so geoip RF → **Direct**.
4. **Custom diversion group** (`work-vpn`): Settings → Work domains → **Copy Karing rules** → Domain Suffix → **Direct**.
5. Start **Karing** first, then **Connect** work VPN here.

See [docs/tunnel-engine.md](docs/tunnel-engine.md) for architecture. Helper licensing: [THIRD_PARTY.md](THIRD_PARTY.md).

## Build from source

```bash
make helper   # builds Vendor/snx-rs → TunnelHelper/dist
make install  # signs, embeds helper, installs to ~/Applications
```

Other targets:

```bash
make build
make test
make generate
make dmg
```

### Manual test plan (clean Mac)

1. Install only this app (no SNX-RS.pkg).
2. Install / repair helper (admin once); confirm `/var/run/checkpoint-vpn.sock` and LaunchDaemon `local.checkpointvpn.tunnel`.
3. Connect: corp routes present, no default via tunnel (`default_route=false` in status).
4. With Karing + Direct rules: corp via work VPN; general internet via Karing; RF Direct.
5. Sleep/wake → Repair or auto-restart → Connect again.
6. Disconnect work VPN: corp breaks; Karing still works.

To publish a GitHub release DMG: **Actions → Release DMG → Run workflow**.
