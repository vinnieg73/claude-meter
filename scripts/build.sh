#!/bin/bash
# Builds build/ClaudeMeter.app. With --install, moves it to ~/Applications (replacing the old one)
# and launches it.
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
  # Notification Center draws the icon it cached for the bundle id, not the app's current one, so
  # note whether this install changes it.
  NEW_ICON=1
  cmp -s "$HOME/Applications/ClaudeMeter.app/Contents/Resources/AppIcon.icns" Resources/AppIcon.icns && NEW_ICON=0
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/ClaudeMeter.app"
  cp -R "$APP" "$HOME/Applications/"
  # One app per bundle id: with the build copy around too, macOS registers it (on its own, moments
  # after it appears) and picks between them. Installed, it has no further use. Then have macOS
  # re-read the installed one.
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LSREGISTER" -u "$PWD/$APP" 2>/dev/null || true
  rm -rf "$APP"
  "$LSREGISTER" -f "$HOME/Applications/ClaudeMeter.app" || true
  # Restarted (it relaunches by itself), Notification Center looks the icon up again.
  if [[ $NEW_ICON == 1 ]]; then killall NotificationCenter 2>/dev/null || true; fi
  open "$HOME/Applications/ClaudeMeter.app"
  # open returns at once, even for an app that crashes on launch: wait to see it running.
  for _ in $(seq 50); do pgrep -f "$RUNNING" >/dev/null && break; sleep 0.2; done
  if ! pgrep -f "$RUNNING" >/dev/null; then
    echo "Installed to ~/Applications/ClaudeMeter.app, but it isn't running (crashed at launch?)" >&2
    exit 1
  fi
  echo "Installed to ~/Applications/ClaudeMeter.app"
fi
