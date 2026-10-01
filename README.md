# Checkpoint VPN One-Click

Menu bar helper that connects **Check Point** VPN via [snx-rs](https://github.com/ancwrd1/snx-rs) (`snxctl`) using a saved password + fresh TOTP — no official Check Point UI automation.

This is not affiliated with Check Point. Install snx-rs separately; this app only drives its CLI.

## Features

- **Connect / Disconnect** Check Point through `snxctl` (password + MFA code)
- **Per-site secrets**: each VPN hostname has its own password and TOTP (Base32, `otpauth://`, or QR)
- **Site picker** in the menu bar (`Check Point site`)
- **Live TOTP** preview in Settings for the selected site
- **Login type** setting (from `snx-rs -m info`, e.g. `vpn_VPN_RA`)
- **Red Shield VPN** (optional): if `/Applications/Red Shield VPN.app` is installed, switch exclusively between Check Point (snx-rs) and Red Shield from the menu or Settings

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
- Optional: [Red Shield VPN](https://redshieldvpn.com/) in `/Applications/Red Shield VPN.app` (needs Accessibility to click Connect)

If the official Check Point Endpoint Security client is also installed, **disconnect it manually** before using snx-rs — route conflicts are on you.

Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) are needed only to build from source. Skip them if you install the DMG.

## Setup

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
5. Connect from the menu bar or Settings.

Check Point via snx-rs does **not** need Accessibility. If you use Red Shield, enable Accessibility for this app so it can click Red Shield’s Connect switch.

If Red Shield is installed, use **Switch to Red Shield** / **Switch to Check Point** (or the Settings toggle). Only one of the two stays connected.

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
