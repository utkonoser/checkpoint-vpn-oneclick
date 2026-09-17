# Checkpoint VPN One-Click

Menu bar helper for **Check Point Endpoint Security VPN** on macOS. It fills the official client’s login and TOTP fields so you can connect without typing the 2FA code from a phone.

This is not a VPN client and is not affiliated with Check Point. The official Endpoint Security app must already be installed.

## Download

- [v1.0.0 DMG](https://github.com/utkonoser/checkpoint-vpn-oneclick/releases/tag/v1.0.0)
- [Latest release](https://github.com/utkonoser/checkpoint-vpn-oneclick/releases/latest)

The GitHub build is ad-hoc signed (no Apple Developer ID). After dragging the app to `/Applications`, right-click → **Open** the first time, or run `xattr -dr com.apple.quarantine /Applications/CheckpointVPNOneClick.app`. A DMG update may require turning Accessibility back on.

To cut a new release: **Actions → Release DMG → Run workflow**, tag like `v1.0.1`.

## Requirements

- macOS 14+
- [Check Point Endpoint Security VPN](https://support.checkpoint.com/) (`/Applications/Endpoint Security VPN.app` and `trac`)
- Xcode
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Install

```bash
make install
```

This builds the app, signs it with a local certificate, and copies it to `~/Applications/CheckpointVPNOneClick.app`.

Then:

1. Open the app from `~/Applications` (not from Xcode’s DerivedData).
2. System Settings → Privacy & Security → **Accessibility** → enable Checkpoint VPN.
3. Quit from the menu bar and open `~/Applications/CheckpointVPNOneClick.app` again.
4. Allow **System Events** if macOS asks (Automation).
5. Settings: site, username, VPN password, TOTP secret (Base32, `otpauth://`, or QR).
6. Connect from the menu bar or Settings.

## Build / test without installing

```bash
make build
make test
```

`make generate` only regenerates `CheckpointVPNOneClick.xcodeproj` from `project.yml`.
