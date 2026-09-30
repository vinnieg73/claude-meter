#!/bin/bash
# Removes Claude Meter and everything it put on this Mac: the app, its login item, its data
# and cache, its preferences, and the statusline entry it added to ~/.claude/settings.json.
set -euo pipefail

APP="$HOME/Applications/ClaudeMeter.app"

pkill -x ClaudeMeter || true
for _ in $(seq 50); do pgrep -x ClaudeMeter >/dev/null || break; sleep 0.1; done
if [[ -x "$APP/Contents/MacOS/ClaudeMeter" ]]; then
  "$APP/Contents/MacOS/ClaudeMeter" --unregister-login
fi

# Only a statusline that is exactly the tap; one that also runs something else is left for
# you to edit. Written to a temp file and renamed, so Claude Code never sees half a file.
python3 - <<'EOF' || echo "statusline entry: couldn't update ~/.claude/settings.json; remove it by hand"
import json, os, tempfile
path = os.path.expanduser("~/.claude/settings.json")
if os.path.exists(path):
    with open(path) as f:
        settings = json.load(f)
    command = str((settings.get("statusLine") or {}).get("command", "")).strip().strip('"').strip("'")
    if command.endswith("/claude-meter-tap"):
        del settings["statusLine"]
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
        with os.fdopen(fd, "w") as f:
            json.dump(settings, f, indent=2)
            f.write("\n")
        os.replace(tmp, path)
        print("statusline entry: removed")
    elif "claude-meter-tap" in command:
        print("statusline entry: runs the tap alongside something else; left for you to edit")
EOF

rm -rf "$APP" \
  "$HOME/Library/Application Support/ClaudeMeter" \
  "$HOME/Library/Caches/ClaudeMeter"
defaults delete local.vinnie.ClaudeMeter 2>/dev/null || true
echo "Claude Meter removed."
