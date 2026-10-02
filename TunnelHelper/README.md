# Tunnel helper payload

Built binaries land in `dist/` (gitignored):

- `CheckpointVPNTunnel` — root daemon (`snx-rs -m command` fork)
- `checkpoint-vpnctl` — CLI used for `connect`
- `local.checkpointvpn.tunnel.plist` — LaunchDaemon

```bash
./Scripts/build-tunnel-helper.sh
./Scripts/bundle-tunnel-helper.sh /path/to/CheckpointVPNOneClick.app
```

Socket: `/var/run/checkpoint-vpn.sock`  
Label: `local.checkpointvpn.tunnel`
