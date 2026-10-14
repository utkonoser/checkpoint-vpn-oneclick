# Checkpoint VPN One-Click

Clients for **Check Point** remote access on **macOS** and **Android**. Both use a vendored [snx-rs](https://github.com/ancwrd1/snx-rs) AGPL fork (`snxcore`) and connect with a saved password + live TOTP — no official Check Point UI.

**Split-tunnel by default** (`default-route=false`): the VPN does not take the whole internet. Optionally list **CIDRs / IPs / hostnames** so only those destinations go through the tunnel.

| Platform | UI | Tunnel |
|----------|----|--------|
| macOS | Menu bar Swift app | Root helper + utun (`CheckpointVPNTunnel`) |
| Android | Jetpack Compose | `VpnService` + `libcheckpoint_engine.so` (JNI → snxcore) |

Not affiliated with Check Point.

See [android/README.md](android/README.md) for Android build / sideload.

## Features

- **Menu bar**: active tunnels, Gateway switcher, Connect or Disconnect for each VPN, Disconnect All, Settings
- **Embedded helper**: first Connect installs LaunchDaemon `local.checkpointvpn.tunnel` (admin once); later connects do not ask again. **Repair tunnel helper…** in Settings if the helper is missing or wedged
- **Connections**: each VPN is its own row (renameable, green/red status). **Add** a Check Point gateway or a subscription proxy
- **Split tunnel**: optional CIDR / IP / hostname list → `no-routing` + `add-routes` (hostnames resolve at Connect)
- **Exclude**: destinations kept off that tunnel. Work VPN uses `ignore-routes`; the personal proxy drops the same entries from its include routes
- **Personal proxy (macOS)**: optional embedded sing-box, started and stopped on its own. Subscription URL, include-only routes, exclude list, Auto or a named node (list sorted by ping)
- **Gateway routes** when the work list is empty (Office Mode from the gateway, still no default route)
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
| Admin once per helper | Work tunnel: `/Library/Application Support/CheckpointVPNTunnel`. Personal proxy: `/Library/Application Support/CheckpointVPNProxy` |
| From source | Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Rust (`cargo`) for the helper |

**Conflicts:** disconnect the official Check Point Endpoint client and upstream snx-rs (`com.github.snx-rs`) before connecting — two IPsec stacks fight over routes.

## Quick setup

1. Install / open the app (`~/Applications` or `/Applications`).
2. Open the **Check Point** connection: gateway hostname, username, login type (usually `vpn_VPN_RA`).
3. Password and TOTP (or import QR), then **Save secrets**.
4. Optional **Split tunnel** and **Exclude from this VPN** — one destination per line:

   ```text
   10.0.0.0/8
   172.16.0.0/12
   intranet.example.com
   ```

5. **Connect** from the menu bar or Settings (helper install runs automatically when needed).

Personal proxy (macOS only): expand that connection, set a subscription URL, then **Include** / **Exclude** the same way (one host, IP, or CIDR per line). **Connect** starts sing-box and routes only the include list. Pick **Auto** or a node; after connect the list sorts by lowest ping.

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
Idle
────────
Active VPNs
None
────────
Gateway ▸
Connect Check Point
Connect Personal proxy
────────
Settings…
────────
Quit
```

When a tunnel is up, its row shows under **Active VPNs** and the button switches to **Disconnect**. **Disconnect All** appears only when more than one is running. The two tunnels do not stop each other.

## Architecture (short)

| Piece | Role |
|-------|------|
| Swift menu bar app | UI, secrets, TOTP, connect conf |
| `CheckpointVPNTunnel` | Root daemon (snx-rs command mode fork) |
| Socket | `/var/run/checkpoint-vpn.sock` |
| LaunchDaemon | `local.checkpointvpn.tunnel` |
| `checkpoint-vpn-proxyctl` | Root controller for sing-box (`/var/run/checkpoint-vpn-proxy.sock`, `local.checkpointvpn.proxy`) |

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

GitHub release (DMG + APK): push a tag, then **Actions → Release → Run workflow** with that tag. Builds macOS DMG and Android APK and attaches both to the release.

### Android APK (local)

```bash
make apk
# → build/CheckpointVPNOneClick.apk
```

Needs JDK 17+, Android SDK/NDK, Rust + `cargo-ndk` (Gradle `preBuild` compiles `libcheckpoint_engine.so`).

PR CI for Android only: **Actions → Android** (`.github/workflows/android.yml`).

### After sleep / helper issues

Settings → **Repair tunnel helper…**, or:

```bash
sudo launchctl kickstart -k system/local.checkpointvpn.tunnel
```
