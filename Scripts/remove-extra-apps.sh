#!/bin/bash
# Spotlight/Launchpad index every CheckpointVPNOneClick.app they can see.
# Keep the installed copy; drop the rest.
set -euo pipefail

KEEP="${1:-$HOME/Applications/CheckpointVPNOneClick.app}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$KEEP" ]]; then
  echo "No installed app at $KEEP; leaving build copies in place." >&2
  exit 0
fi
keep="$(cd "$KEEP" && pwd -P)"

roots=("$HOME/Applications" /Applications "$ROOT/build")
if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
  roots+=("$HOME/Library/Developer/Xcode/DerivedData")
fi

while IFS= read -r app; do
  [[ -d "$app" ]] || continue
  real="$(cd "$app" && pwd -P)"
  [[ "$real" == "$keep" ]] && continue
  echo "Removing extra copy $app"
  "$LSREG" -u "$app" >/dev/null 2>&1 || true
  rm -rf "$app"
done < <(find "${roots[@]}" -name 'CheckpointVPNOneClick.app' -type d -prune -print 2>/dev/null)

"$LSREG" -f "$keep" >/dev/null 2>&1 || true
