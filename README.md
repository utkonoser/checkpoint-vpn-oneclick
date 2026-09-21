# Checkpoint VPN One-Click

Menu bar helper for **Check Point Endpoint Security VPN** on macOS. It opens the official client, fills login + TOTP, and connects without typing the 2FA code from a phone.

This is not a VPN client and is not affiliated with Check Point. The official Endpoint Security app must already be installed.

## Features

- **Connect / Disconnect** Check Point from the menu bar
- **Per-site secrets**: each Check Point site has its own password and TOTP (Base32, `otpauth://`, or QR)
- **Site picker** in the menu bar (`Check Point site`)
- **Live TOTP** preview in Settings for the selected site
- **Fast fail** if the tunnel stays Idle; retries login + OTP if Check Point bounces back to the login form or shows Access Denied
- **Red Shield VPN** (optional): if `/Applications/Red Shield VPN.app` is installed, switch exclusively between Check Point and Red Shield from the menu or Settings
- Opens Check Point / Red Shield when their windows are closed (tray-only is not enough)

Secrets are stored in `~/Library/Application Support/CheckpointVPNOneClick/secrets.plist` (mode `0600`), not in the login Keychain — so ad-hoc rebuilds do not spam Keychain password dialogs.

## Download

- [v1.0.0 DMG](https://github.com/utkonoser/checkpoint-vpn-oneclick/releases/tag/v1.0.0)
- [Latest release](https://github.com/utkonoser/checkpoint-vpn-oneclick/releases/latest)

The GitHub build is ad-hoc signed (no Apple Developer ID). Drag the app to `/Applications`, then right-click → **Open** the first time, or run:

```bash
xattr -dr com.apple.quarantine /Applications/CheckpointVPNOneClick.app
```

A DMG update may require turning Accessibility back on.

## Requirements

- macOS 14+
- [Check Point Endpoint Security VPN](https://support.checkpoint.com/) (`/Applications/Endpoint Security VPN.app` and `trac`)
- Optional: [Red Shield VPN](https://redshieldvpn.com/) in `/Applications/Red Shield VPN.app`

Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) are needed only to build from source. Skip them if you install the DMG.

## Setup

1. Open the installed app from `~/Applications` or `/Applications` (not from Xcode DerivedData).
2. System Settings → Privacy & Security → **Accessibility** → enable **Checkpoint VPN**.
3. Quit from the menu bar and open the app again (Accessibility sticks after that restart).
4. Allow **System Events** if macOS asks (Automation).
5. **Settings**:
   - Pick a Check Point site (or type one)
   - Username
   - Password + TOTP for **that** site
6. Connect from the menu bar or Settings. Use **Check Point site** in the menu to switch sites; secrets follow the selected site.

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
