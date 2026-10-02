# Third-party notices

## snx-rs (tunnel engine)

- Project: [ancwrd1/snx-rs](https://github.com/ancwrd1/snx-rs)
- Upstream pin: see `Vendor/snx-rs.COMMIT`
- License: **GNU Affero General Public License v3.0** (AGPL-3.0) — see `Vendor/snx-rs/COPYING`
- Use in this app: vendored source under `Vendor/snx-rs`, built as `CheckpointVPNTunnel` / `checkpoint-vpnctl`.
- Local patches vs upstream:
  - socket name `checkpoint-vpn.sock` (was `snx-rs.sock`)
  - lock `/var/run/checkpoint-vpn.lock`
  - forwarding marker `/var/run/checkpoint-vpn.forwarding`
- Obligation: distributing the helper binaries requires offering the corresponding (modified) source; that source is this repository’s `Vendor/snx-rs` tree and packaging scripts under `Scripts/` / `TunnelHelper/`.

This application’s Swift UI is a separate process that controls the helper over a local Unix socket. The AGPL-covered work is the tunnel engine fork.
