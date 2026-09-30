#!/bin/bash
# Builds ClaudeMeter.app. With --install, replaces ~/Applications/ClaudeMeter.app and launches it.
set -euo pipefail
# The running app is the bare binary; `ClaudeMeter --status` or `--render` runs carry flags
# and are left alone.
RUNNING='ClaudeMeter\.app/Contents/MacOS/ClaudeMeter$'
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="build/ClaudeMeter.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ClaudeMeter" "$BIN/claude-meter-tap" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Ad-hoc signature: enough for notifications and login items on this Mac.
codesign --force --sign - "$APP/Contents/MacOS/claude-meter-tap"
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
  # The app saves its index on the way out; `open` would otherwise find it still quitting,
  # hand it the launch, and leave nothing running once it exits.
  pkill -f "$RUNNING" || true
  for _ in $(seq 50); do pgrep -f "$RUNNING" >/dev/null || break; sleep 0.1; done
  pkill -9 -f "$RUNNING" || true
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/ClaudeMeter.app"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/ClaudeMeter.app"
  echo "Installed to ~/Applications/ClaudeMeter.app"
fi
