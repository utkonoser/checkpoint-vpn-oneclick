# Manual test plan (own tunnel helper)

Clean Mac / VM preferred (no `SNX-RS.pkg`).

1. `make helper && make install` — helper under `Contents/Resources/TunnelHelper`.
2. Settings → **Install / repair tunnel helper…** (admin once).
3. Check `/Library/LaunchDaemons/local.checkpointvpn.tunnel.plist`, `/var/run/checkpoint-vpn.sock`, `pgrep -x CheckpointVPNTunnel`.
4. Connect with empty split destinations: gateway routes; no default via tunnel.
5. Add CIDRs / hostnames under **Split destinations**, Connect again: only those routes via tunnel (`no-routing` + `add-routes`).
6. Sleep/wake → Restart / repair → Connect again.
7. Disconnect: listed destinations unreachable via the tunnel path.
8. If upstream `com.github.snx-rs` is present, disconnect it first.
