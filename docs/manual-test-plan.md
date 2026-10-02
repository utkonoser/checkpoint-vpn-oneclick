# Manual test plan (own tunnel helper)

Clean Mac / VM preferred (no `SNX-RS.pkg`).

1. `make helper && make install` (or install DMG). Confirm app opens from `~/Applications`.
2. Settings → **Install / repair tunnel helper…** (admin once).
3. Check:
   - `/Library/LaunchDaemons/local.checkpointvpn.tunnel.plist` exists
   - `/var/run/checkpoint-vpn.sock` appears
   - `pgrep -x CheckpointVPNTunnel`
4. Connect with real gateway credentials. Status shows Connected; corp routes present; `default_route` false in daemon status.
5. With Karing + Direct (work domains / geoip RU): corp via helper; general internet via Karing.
6. Sleep/wake → Settings restart or auto refresh → Connect again.
7. Disconnect: corp unreachable; Karing still works.
8. If upstream `com.github.snx-rs` is present, disconnect it first — do not run both.
