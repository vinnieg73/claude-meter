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

Exception (2026-10-11, asked for by the user): a new app icon, "Night Shift" (design in
design/icon-night-shift/), drawn by scripts/make-icon.swift, done in v0.9.11. Scope is back to bug
elimination.

Exception (2026-10-10, asked for by the user): one notification when exact readings stop (an hour of
Claude Code use with none), done in v0.9.8. Scope is back to bug elimination.

Exception (2026-10-11, asked for by the user): a Fable card showing the separate weekly Fable limit
(read from `claude -p /usage`) and this Mac's Fable share of the overall windows, pink, with a Help
section, done in v0.9.14. Scope is back to bug elimination.

Exception (2026-10-12, asked for by the user): Claude Code mascots in the dropdown ("Option C" from
a mockup the user approved), drawn in `Mascot.swift`: a running crew in the header, still mascots on the
limit cards, running ones in Burning now and eyes-shut ones in Going cold, coloured by model family,
moving only while the dropdown is open. The menu bar is unchanged. Done in v0.9.16; v0.9.17 (also asked for) made
Going cold two-line rows and put Burning now tags under the name so names read. Scope is back to
bug elimination.

Before calling a fix done, run `./scripts/replay.sh` and confirm PASS. It replays the real history
log and transcripts through the working tree (read-only) and checks window openings, the probe
gate, duplicate alerts and accuracy. If a fix guards something the replay doesn't cover, say so.

## Lessons

- Anything that widens a Going cold or Burning now row can push the whole dropdown past 340 pt (it shifts and clips at both edges): check the `long` fixture, which carries the longest tags and amounts (v0.9.16).
- Only the probe measures at its reading's time. A tap.json drop-in from another tool (Claude Dashboard, Oct 12) carried an old weekly 50% while the week was at 59%; taken as measured it faked an early reset and taught a weekly cap of $150. Drop-ins now count like the statusline (v0.9.18).
