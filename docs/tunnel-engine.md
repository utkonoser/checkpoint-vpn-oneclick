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

## Auth / tunnel flow

1. Discover login type: engine `info` mode → e.g. `vpn_VPN_RA`.
2. Connect conf: `server-name`, `login-type`, `user-name`, base64 `password`, `mfa-code`, `tunnel-type=ipsec`, `ignore-server-cert`, **`default-route=false`**.
3. Optional **split destinations** (Settings): resolve hostnames → CIDRs; set `no-routing=true` and `add-routes=...` so only those nets use the tunnel. If the list is empty, gateway Office Mode routes apply.
4. `checkpoint-vpnctl -c conf connect` brings up IPsec via the Unix socket.
5. Status / Disconnect: length-delimited JSON (`GetStatus`, `Disconnect`).

## Coexistence

If upstream `com.github.snx-rs` is also installed, disconnect it before using this app — two IPsec clients fight over routes.

## License

Upstream engine is **AGPL-3.0** ([ancwrd1/snx-rs](https://github.com/ancwrd1/snx-rs)). See [THIRD_PARTY.md](../THIRD_PARTY.md). The vendored tree under `Vendor/snx-rs` (plus our socket-path patch) is the corresponding source for the shipped helper binaries.
