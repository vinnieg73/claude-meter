#!/bin/bash
# Builds ClaudeMeter.app. With --install, replaces ~/Applications/ClaudeMeter.app and launches it.
set -euo pipefail
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
  pkill -x ClaudeMeter || true
  rm -rf "$HOME/Applications/ClaudeMeter.app"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/ClaudeMeter.app"
  echo "Installed to ~/Applications/ClaudeMeter.app"
fi
