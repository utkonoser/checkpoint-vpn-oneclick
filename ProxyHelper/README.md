# Personal proxy helper (sing-box)

Embedded [sing-box](https://github.com/SagerNet/sing-box) for dual-VPN: Check Point Office Mode + include-only personal proxy.

```bash
./Scripts/build-sing-box.sh
./Scripts/bundle-proxy-helper.sh /path/to/CheckpointVPNOneClick.app
```

System install path: `/Library/Application Support/CheckpointVPNProxy/`  
LaunchDaemon label: `local.checkpointvpn.proxy` (started on demand, not at login).
