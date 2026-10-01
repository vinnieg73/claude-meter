#!/bin/bash
# Builds the working tree and replays this Mac's history through it (ClaudeMeter --replay).
# Reads the real logs and history; writes nothing. Exits non-zero if any check fails.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --quiet
"$(swift build -c release --show-bin-path)/ClaudeMeter" --replay
