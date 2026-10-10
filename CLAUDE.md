# Claude Meter

Menu bar meter for Claude plan limits. See README.md for how it works.

## Scope

The tool is feature-complete. Work here is bug elimination only: no new features, no
redesigns, no new settings. A fix may touch any code it needs to, but should not change what
the meter shows or does beyond correcting the bug.

Exception (2026-10-06, asked for by the user): a one-time visual pass, done in v0.9.0. Scope is back
to bug elimination.

Exception (2026-10-08, asked for by the user): a Help window (right-click → Help…, or the gear menu)
that explains everything the meter shows in plain words, done in v0.9.4. Scope is back to bug
elimination. When a fix touches a view, check it with `scripts/render-all.sh <dir>` (every
state, light and dark, from `Fixtures.swift`).

Exception (2026-10-09, asked for by the user): Burning now and Going cold name sessions by the
desktop app's thread title, and tag rows that share a name with when each last ran, done in v0.9.5;
in v0.9.6 (also asked for) the model moved to the row's tooltip so names fit. Scope is back to bug
elimination.

Before calling a fix done, run `./scripts/replay.sh` and confirm PASS. It replays the real history
log and transcripts through the working tree (read-only) and checks window openings, the probe
gate, duplicate alerts and accuracy. If a fix guards something the replay doesn't cover, say so.
