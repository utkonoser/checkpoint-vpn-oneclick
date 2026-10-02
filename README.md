# Checkpoint VPN One-Click

Menu bar helper that connects **Check Point** VPN via [snx-rs](https://github.com/ancwrd1/snx-rs) (`snxctl`) using a saved password + fresh TOTP — no official Check Point UI automation.

This is not affiliated with Check Point. Install snx-rs separately; this app only drives its CLI.

Use this app for **work VPN only** (split-tunnel). For the rest of the internet, run [Karing](https://karing.app) (or similar) with Direct rules for work domains / RF IPs so the two do not fight over the default route.

## Features

- **Connect / Disconnect** Check Point through `snxctl` (password + MFA code)
- **Split-tunnel by default**: `default-route=false` — keeps gateway-pushed corporate routes, does not own all internet
- **Per-site secrets**: each VPN hostname has its own password and TOTP (Base32, `otpauth://`, or QR)
- **Site picker** in the menu bar (`Check Point site`)
- **Live TOTP** preview in Settings for the selected site
- **Login type** setting (from `snx-rs -m info`, e.g. `vpn_VPN_RA`)
- **Work domains** list + **Copy Karing rules** for Direct diversion alongside Karing

Secrets are stored in `~/Library/Application Support/CheckpointVPNOneClick/secrets.plist` (mode `0600`), not in the login Keychain — so ad-hoc rebuilds do not spam Keychain password dialogs.

## Download

- [v1.0.0 DMG](https://github.com/utkonoser/checkpoint-vpn-oneclick/releases/tag/v1.0.0)
- [Latest release](https://github.com/utkonoser/checkpoint-vpn-oneclick/releases/latest)

The GitHub build is ad-hoc signed (no Apple Developer ID). Drag the app to `/Applications`, then right-click → **Open** the first time, or run:

```bash
xattr -dr com.apple.quarantine /Applications/CheckpointVPNOneClick.app
```

## Requirements

- macOS 14+
- [snx-rs](https://github.com/ancwrd1/snx-rs/releases) — install **SNX-RS.pkg** so `snxctl` / `snx-rs` and the LaunchDaemon are present (`/usr/local/bin/snxctl`)
- Optional: [Karing](https://karing.app) (or another TUN proxy client) for non-corporate traffic

If the official Check Point Endpoint Security client is also installed, **disconnect it manually** before using snx-rs — route conflicts are on you.

Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) are needed only to build from source. Skip them if you install the DMG.

## Setup (work VPN)

1. Install snx-rs (`SNX-RS.pkg` from the [releases](https://github.com/ancwrd1/snx-rs/releases) page).
2. Discover login type (once per gateway):

   ```bash
   snx-rs -m info -s vpn.example.com
   ```

   Use the `vpn_XXX` id (e.g. `vpn_VPN_RA`) in Settings → Login type.
3. Open this app from `~/Applications` or `/Applications`.
4. **Settings**:
   - Site = VPN hostname
   - Username, login type
   - Password + TOTP for **that** site
   - Optional: work domains (one per line) for Karing export
5. Connect from the menu bar or Settings.

Check Point via snx-rs does **not** need Accessibility.

## Using with Karing (both at once)

Goal: **work nets → snx-rs**, **everything else → Karing**, **RF IPs / work domains → Direct** in Karing so they follow macOS routes into the work tunnel.

1. Install [Karing](https://karing.app) and add your subscription / nodes.
2. Enable Karing’s TUN / system proxy as required by the app.
3. **Diversion → Country / Region:** set to **Russia** (or your region) so built-in **geoip** rules for RF use **Direct** (traffic stays on the system stack instead of the proxy).
4. **Custom diversion group** (e.g. `work-vpn`):
   - In this app: Settings → Work domains → **Copy Karing rules**
   - In Karing: Diversion → Custom diversion group → add each **Domain Suffix** from the clipboard → action **Direct**
5. Recommended order: start **Karing** first, then **Connect** work VPN here.
6. If corporate sites still go through the proxy: check Karing diversion detect / rule priority (Direct group must hit). If random internet goes into snx-rs: confirm connect conf has `default-route=false` (this app sets it automatically).

```text
Browser / apps
    ├─ work domain (Karing Direct) ──► macOS routes ──► snx-rs (corp CIDRs from gateway)
    ├─ RF IP (geoip Direct)        ──► macOS routes ──► normal / snx if GW pushed that net
    └─ rest                        ──► Karing proxy node
```

## Build from source

```bash
make install
```

Builds, signs, installs to `~/Applications/CheckpointVPNOneClick.app`, and removes extra copies under the project `build/` tree so Launchpad/Spotlight stay to one app.

Other targets:

```bash
make build    # compile only (then cleans extra .app copies if an install exists)
make test
make generate # regenerate CheckpointVPNOneClick.xcodeproj from project.yml
make dmg      # local DMG under build/
```

To publish a GitHub release DMG: **Actions → Release DMG → Run workflow**, tag like `v1.0.1`.
