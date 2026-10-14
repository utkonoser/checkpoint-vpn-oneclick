#!/usr/bin/env bash
# Root helper for personal proxy (sing-box).
# LaunchDaemon runs `serve` (no password after install). The app talks to the unix socket.
set -euo pipefail

SUPPORT="/Library/Application Support/CheckpointVPNProxy"
BIN="$SUPPORT/sing-box"
CFG="$SUPPORT/sing-box.json"
IFACE="utun223"
ROUTES="$SUPPORT/installed-routes.txt"
SOCK="/var/run/checkpoint-vpn-proxy.sock"

cmd="${1:-}"
shift || true

case "$cmd" in
  serve)
    exec /usr/bin/python3 - "$SOCK" "$BIN" "$CFG" "$IFACE" "$ROUTES" <<'PY'
import os, socket, subprocess, sys, time

sock_path, bin_path, cfg_path, iface, routes_path = sys.argv[1:6]
child = None

def clear_routes():
    if not os.path.exists(routes_path):
        return
    with open(routes_path) as f:
        cidrs = [ln.strip() for ln in f if ln.strip()]
    for cidr in cidrs:
        subprocess.call(["/sbin/route", "-n", "delete", "-net", cidr, "-interface", iface],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        os.remove(routes_path)
    except OSError:
        pass

def set_routes(cidrs):
    clear_routes()
    os.makedirs(os.path.dirname(routes_path), exist_ok=True)
    kept = []
    for cidr in cidrs:
        subprocess.call(["/sbin/route", "-n", "delete", "-net", cidr, "-interface", iface],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        rc = subprocess.call(["/sbin/route", "-n", "add", "-net", cidr, "-interface", iface],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if rc == 0:
            kept.append(cidr)
    with open(routes_path, "w") as f:
        f.write("\n".join(kept) + ("\n" if kept else ""))
    return "ok" if len(kept) == len(cidrs) else "err some routes failed"

def stop_child():
    global child
    clear_routes()
    if child is not None and child.poll() is None:
        child.terminate()
        try:
            child.wait(timeout=3)
        except subprocess.TimeoutExpired:
            child.kill()
    child = None
    subprocess.call(["/usr/bin/killall", "sing-box"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def start():
    global child
    stop_child()
    if not os.path.isfile(cfg_path):
        return "err missing config"
    child = subprocess.Popen([bin_path, "run", "-c", cfg_path])
    for _ in range(20):
        if subprocess.call(["/sbin/ifconfig", iface],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0:
            return "ok"
        if child.poll() is not None:
            return "err sing-box exited"
        time.sleep(0.3)
    return "err utun not up"

def apply_config(src):
    if not src or not os.path.isfile(src):
        return "err missing source config"
    os.makedirs(os.path.dirname(cfg_path), exist_ok=True)
    data = open(src, "rb").read()
    tmp = cfg_path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.chmod(tmp, 0o644)
    os.replace(tmp, cfg_path)
    return "ok"

def handle(line):
    parts = line.strip().split()
    if not parts:
        return "err empty"
    op = parts[0]
    if op == "ping":
        return "ok"
    if op == "apply-config":
        # Path may contain spaces (e.g. "Application Support").
        return apply_config(" ".join(parts[1:]) if len(parts) > 1 else "")
    if op == "start":
        return start()
    if op == "stop":
        stop_child()
        return "ok"
    if op == "set-routes":
        return set_routes(parts[1:])
    if op == "clear-routes":
        clear_routes()
        return "ok"
    return "err unknown"

try:
    os.unlink(sock_path)
except OSError:
    pass
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(sock_path)
os.chmod(sock_path, 0o666)
srv.listen(8)
while True:
    conn, _ = srv.accept()
    try:
        data = b""
        while b"\n" not in data and len(data) < 65536:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
        line = data.decode("utf-8", "replace").split("\n", 1)[0]
        reply = handle(line)
        conn.sendall((reply + "\n").encode())
    except Exception as e:
        try:
            conn.sendall(("err " + str(e) + "\n").encode())
        except Exception:
            pass
    finally:
        conn.close()
PY
    ;;
  *)
    echo "usage: $0 serve" >&2
    exit 1
    ;;
esac
