# Third-party notices

## snx-rs (tunnel engine)

- Project: [ancwrd1/snx-rs](https://github.com/ancwrd1/snx-rs)
- Upstream pin: see `Vendor/snx-rs.COMMIT`
- License: **GNU Affero General Public License v3.0** (AGPL-3.0) — see `Vendor/snx-rs/COPYING`
- Use in this app:
  - macOS: built as `CheckpointVPNTunnel` / `checkpoint-vpnctl`
  - Android: linked into `libcheckpoint_engine.so` (`android/engine`) via JNI
- Local patches vs upstream:
  - socket name `checkpoint-vpn.sock` (was `snx-rs.sock`)
  - lock `/var/run/checkpoint-vpn.lock`
  - forwarding marker `/var/run/checkpoint-vpn.forwarding`
  - Android platform module (`crates/snxcore/src/platform/android/`) — VpnService TUN fd, routes/DNS owned by Kotlin
- Obligation: distributing the helper / APK native library requires offering the corresponding (modified) source; that source is this repository’s `Vendor/snx-rs` tree, `android/engine`, and packaging scripts under `Scripts/` / `TunnelHelper/`.

The macOS Swift UI and Android Compose UI are separate processes that control the AGPL-covered tunnel engine (Unix socket on macOS; in-process JNI on Android).
