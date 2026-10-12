#!/bin/bash
# Renders the dropdown in every fixture state and from the live logs, History, Help, and the menu
# bar ring, light and dark, into a folder (ClaudeMeter --render). Reads only; writes just the PNGs.
set -euo pipefail
[[ $# -eq 1 ]] || { echo "usage: scripts/render-all.sh <outdir>"; exit 1; }
mkdir -p "$1"
OUT="$(cd "$1" && pwd)"
cd "$(dirname "$0")/.."
swift build --quiet
BIN="$(swift build --show-bin-path)/ClaudeMeter"

for f in live calm warn critical idle empty loading trouble week long nofable; do
  for look in light dark; do
    args=(--render "$OUT/popover-$f-$look.png")
    [[ $f == live ]] || args+=(--fixture "$f")
    [[ $look == dark ]] && args+=(--dark)
    "$BIN" "${args[@]}" >/dev/null || { echo "render failed: ${args[*]}"; exit 1; }
  done
done
for f in live fits uncalibrated; do
  for look in light dark; do
    args=(--render "$OUT/history-$f-$look.png" --history)
    [[ $f == live ]] || args+=(--fixture "$f")
    [[ $look == dark ]] && args+=(--dark)
    "$BIN" "${args[@]}" >/dev/null || { echo "render failed: ${args[*]}"; exit 1; }
  done
done
for look in light dark; do
  args=(--render "$OUT/help-$look.png" --help-page)
  [[ $look == dark ]] && args+=(--dark)
  "$BIN" "${args[@]}" >/dev/null || { echo "render failed: ${args[*]}"; exit 1; }
done
"$BIN" --render "$OUT/icons.png" --icons >/dev/null || { echo "render failed: icons"; exit 1; }
echo "rendered to $OUT"
