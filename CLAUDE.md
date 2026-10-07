# Claude Meter

Menu bar meter for Claude plan limits. See README.md for how it works.

## Scope

The tool is feature-complete. Work here is bug elimination only: no new features, no
redesigns, no new settings. A fix may touch any code it needs to, but should not change what
the meter shows or does beyond correcting the bug.

Exception (2026-10-06, asked for by the user): a one-time visual pass on the `visual-pass` branch.
It may change how things look, not what the meter shows or does: no new information, controls or
settings. Check looks with `scripts/render-all.sh <dir>` (every state, light and dark).

Before calling a fix done, run `./scripts/replay.sh` and confirm PASS. It replays the real history
log and transcripts through the working tree (read-only) and checks window openings, the probe
gate, duplicate alerts and accuracy. If a fix guards something the replay doesn't cover, say so.
