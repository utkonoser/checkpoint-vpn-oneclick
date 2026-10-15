# Third-party notices

## snx-rs (tunnel engine)

- Project: [ancwrd1/snx-rs](https://github.com/ancwrd1/snx-rs)
- Upstream pin: see `Vendor/snx-rs.COMMIT`
- License: **GNU Affero General Public License v3.0** (AGPL-3.0) — see `Vendor/snx-rs/COPYING`
- Use in this app: built as `CheckpointVPNTunnel` / `checkpoint-vpnctl`
- Local patches vs upstream:
  - socket name `checkpoint-vpn.sock` (was `snx-rs.sock`)
  - lock `/var/run/checkpoint-vpn.lock`
  - forwarding marker `/var/run/checkpoint-vpn.forwarding`
- Obligation: distributing the helper requires offering the corresponding (modified) source; that source is this repository’s `Vendor/snx-rs` tree and packaging scripts under `Scripts/` / `TunnelHelper/`.

The macOS Swift UI is a separate process that controls the AGPL-covered tunnel engine over a Unix socket.

## sing-box (personal proxy helper)

- Project: [SagerNet/sing-box](https://github.com/SagerNet/sing-box)
- License: **GNU General Public License v3.0** (GPL-3.0)
- Use in this app: bundled binary under `ProxyHelper/` / `/Library/Application Support/CheckpointVPNProxy/` for optional dual-VPN include-only routing on macOS.
- Build: `Scripts/build-sing-box.sh` downloads the official darwin release (override with `SING_BOX_VERSION=`).
