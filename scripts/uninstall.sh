#!/bin/bash
# Removes Claude Meter and everything it put on this Mac: the app, its login item, its data
# and cache, its preferences, and the statusline entry it added to ~/.claude/settings.json.
set -euo pipefail

APP="$HOME/Applications/ClaudeMeter.app"

pkill -x ClaudeMeter || true
if [[ -x "$APP/Contents/MacOS/ClaudeMeter" ]]; then
  "$APP/Contents/MacOS/ClaudeMeter" --unregister-login
fi

# Only the statusline entry that points at the tap; anything else there is left alone.
python3 - <<'EOF'
import json, os
path = os.path.expanduser("~/.claude/settings.json")
if os.path.exists(path):
    settings = json.load(open(path))
    if "claude-meter-tap" in (settings.get("statusLine") or {}).get("command", ""):
        del settings["statusLine"]
        json.dump(settings, open(path, "w"), indent=2)
        open(path, "a").write("\n")
        print("statusline entry: removed")
EOF

rm -rf "$APP" \
  "$HOME/Library/Application Support/ClaudeMeter" \
  "$HOME/Library/Caches/ClaudeMeter"
defaults delete local.vinnie.ClaudeMeter 2>/dev/null || true
echo "Claude Meter removed."
