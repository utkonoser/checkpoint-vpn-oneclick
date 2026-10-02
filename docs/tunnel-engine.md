# Tunnel engine (own helper, snx-rs based)

## Why not Network Extension

This project is distributed ad-hoc (no Apple Developer Program). `NEPacketTunnelProvider` requires Developer ID entitlements and notarization, so the tunnel runtime is a **root LaunchDaemon + utun**, same class as upstream snx-rs.

## Components

| Piece | Role |
|-------|------|
| `CheckpointVPNOneClick` (Swift) | Menu bar UI, secrets, TOTP, connect conf |
| `CheckpointVPNTunnel` | Root daemon (`snx-rs -m command` fork) |
| `checkpoint-vpnctl` | CLI client (snxctl fork) used for `connect` |
| Socket | `/var/run/checkpoint-vpn.sock` |
| LaunchDaemon | `local.checkpointvpn.tunnel` |

The app never talks to system `/usr/local/bin/snxctl` or `/var/run/snx-rs.sock`.

## Auth / tunnel flow (reference)

1. Discover login type: `checkpoint-vpnctl` / engine `info` mode → e.g. `vpn_VPN_RA`.
2. Connect conf (written by the app): `server-name`, `login-type`, `user-name`, base64 `password`, `mfa-code`, `tunnel-type=ipsec`, `ignore-server-cert`, **`default-route=false`** (split-tunnel; keep GW Office Mode routes).
3. `checkpoint-vpnctl -c conf connect` asks the daemon over the Unix socket to bring up IPsec.
4. Status / Disconnect: length-delimited JSON over the socket (`GetStatus`, `Disconnect`) — same wire shape as upstream snx-rs command mode.
5. Routes/DNS: engine applies gateway-pushed routes onto utun; with `default-route=false` the rest of the internet stays for Karing (or the system).

## Coexistence

- If upstream `com.github.snx-rs` is also installed, disconnect it before using this app — two IPsec clients fight over routes.
- Karing: work domains / geoip RU → Direct so traffic hits macOS routes → our utun.

## License

Upstream engine is **AGPL-3.0** ([ancwrd1/snx-rs](https://github.com/ancwrd1/snx-rs)). See [THIRD_PARTY.md](../THIRD_PARTY.md). The vendored tree under `Vendor/snx-rs` (plus our socket-path patch) is the corresponding source for the shipped helper binaries.
