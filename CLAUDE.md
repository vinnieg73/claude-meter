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

Exception (2026-10-26, asked for by the user): same-named rows in Burning now and Going cold are tagged with when
each session started ("Started 1:05 PM"; "· started 12:21 PM" on a cold row), not when it last ran, so a burning and a
cold "Pocket Fishing" read as two sessions. Last ran stays as the fallback. Done in v0.9.29. Scope is back to bug
elimination.

Exception (2026-10-17, asked for by the user): Remote Control sessions the desktop app left on its
placeholder title are named by the app's summary of their last turn, else their project, done in
v0.9.19. Scope is back to bug elimination.

Exception (2026-10-19, asked for by the user): "Value this week" in History (option A of the mockup
https://claude.ai/artifact/HDDp8xFFM5aW9RoCLEy7s7): the week so far at pay-as-you-go prices against the
plan's weekly price (Plan in History.swift holds the prices), by day and model, and one line under the
weekly card that opens History, done in v0.9.23. Scope is back to bug elimination.

Exception (2026-10-25, asked for by the user): one cloud feed shared by Meter, Dashboard and Swarm Watch. The meter
reads Anthropic's sessions list (Swarm Watch's reader, GET only, the Claude Code sign-in held in memory) every 5 minutes
and books each cloud session's exact `cost_usd` into `cloud.json` (`CloudFeed.swift`). Value this week becomes this Mac +
Cloud sessions (exact) + Other (the estimate, was "Elsewhere"), "This week" lists cloud sessions by title, and cloud spend
counts in calibration, the estimate between readings and the pace, so cloud use no longer shrinks the cap. A right-click
setting "Cloud sessions" (on), `--cloud-check`, and cloud lines in `--status`. Done in v0.9.26. Scope is back to bug
elimination.

Exception (2026-10-27, asked for by the user): an API credits card for the Console's prepaid credits (mockup
https://claude.ai/artifact/2G5n3LjuH6XWtyBfmZhVBt). The balance is typed in (gear or right-click → API credits…); a
Console key in the keychain adds real spend from the Admin API's cost report (`Credits.swift`). `--credits-check`, lines
in `--status`, fixtures `credits`, `creditslow`, `creditstyped`, `creditsexpired`. Also asked for: a Usage credits card
for claude.ai extra usage (monthly spend vs limit, prepaid balance), read with the Claude Code sign-in from
`/api/oauth/usage` and `.../prepaid/credits` (`PlanCredits`, `--extra-check`). With both cards the dropdown could outgrow
the screen, so the live dropdown's modules now scroll past the screen's height (`capToScreen`; renders draw it whole).
Done in v0.9.30. Scope is back to bug elimination.

Exception (2026-10-28, asked for by the user: "move everything that has to do with API credits to its own tab"): the
dropdown has two tabs under the header, Usage and Credits (`DropdownTabs`, `dropdownTab` default); both credit cards
moved to Credits, with a Set up note when no balance is typed and a red dot on the Credits tab while a card there is red
(`CreditsView.alarm`, `limitReached`). Fixtures `creditsalert`, `nocredits`; the credits fixtures render the Credits tab.
Done in v0.9.32. Scope is back to bug elimination.
Same release (asked for: "can we fix them first"): the replay fed no cloud spend, so it failed 4 checks on a meter
that was fine; it now replays cloud.json's ledger and checks the probe gate after resets opened away from this Mac.
v0.9.33 (asked for: the red dot "reads like a notification"; then "go ahead with your recs"): no dot. The tabs say their
headline in words ("Usage · 62%", "Credits · $107 left", red "Credits · out Nov 11"), and while extra usage is off the
5-hour and weekly cards say so from 70% (`ExtraOffLine`).

Exception (2026-10-29, asked for by the user: Claude Duet usage, "a completely inclusive and holistic overview", "as long
as it doesnt make things too crowded"): one gray line under the weekly card, "Share by app: Code 86% · Chat 8% · Cowork 4% ·
Duet 2%", from `seven_day_breakdown` in the usage read (`PlanCredits.Surface`, `weekSurfaces`), repeated under Value this
week in History and in `--status`. Done in v0.9.34. Scope is back to bug elimination.

Exception (2026-10-30, asked for by the user: "familiarized with the new changes to the claude plans", then approved the
mockups "that looks good"): Max 20x became Ultra (10x Pro weekly, no 5-hour limit once Anthropic verifies the account).
Plans read Pro, Max, Ultra (raw values unchanged), Plan fit uses per-window multipliers, and the meter switches itself to
week-only (no 5-hour card, alerts or History windows; menu bar "41% · 3d4h"; burn %/hr of the week; probes gated on recent
use) once two usage reports list no `session` limit, back on the first that lists one (`fiveHourGoneSince`, fixture
`ultra`, a synthetic replay case, a "5-hour limit:" line in `--status`). Built ahead of his account being verified, so
the real switch is untested on live data. Scope is back to bug elimination.

Before calling a fix done, run `./scripts/replay.sh` and confirm PASS. It replays the real history
log and transcripts through the working tree (read-only) and checks window openings, the probe
gate, duplicate alerts and accuracy. If a fix guards something the replay doesn't cover, say so.

Note (2026-10-19, asked for by the user): the status item fits its text (variable length), as before v0.9.20. A fixed
slot (v0.9.20–21) left blank space that Vinnie disliked; v0.9.22 went back. Kept: autosaveName, skipping redraws that
change nothing, tabular digits (the width only changes when the number of characters does).

Note (2026-10-19, asked for by the user, v0.9.24): to fit beside the 58 pt Vitals dials (178.5 pt right of the notch),
a title with the weekly % drops the 5-hour % (the ring shows it): "2h50m wk 41%", at most "cap 10:49 wk ~100%"
(169 pt). The cap time has no AM/PM anywhere in the title (`Fmt.bareClock`; always within 5 hours).

## Lessons

- Anything that widens a Going cold or Burning now row can push the whole dropdown past 340 pt (it shifts and clips at both edges): check the `long` fixture, which carries the longest tags and amounts (v0.9.16).
- Since v0.9.5 any desktop app title beat the project, so its placeholder "Remote Control session (from a project)" named most Remote Control rows; a title source can hold placeholders, not just names (v0.9.19).
- A `variableLength` status item whose title changes width re-lays out the whole menu bar, so icons slide in and out from behind the notch. Keep one fixed `length`; a fixed-length button centres its content, so pad the image to pin it (v0.9.20).
- `Fmt.clock` writes "10:49 PM" with a narrow no-break space (U+202F); a typed "10:49 PM" is 2 pt wider. Measure with the real formatter (v0.9.20). (v0.9.24: the title uses `Fmt.bareClock`, no period, and `Fmt.clock` is gone.)
- Only the probe measures at its reading's time. A tap.json drop-in from another tool (Claude Dashboard, Oct 12) carried an old weekly 50% while the week was at 59%; taken as measured it faked an early reset and taught a weekly cap of $150. Drop-ins now count like the statusline (v0.9.18).
- A window sized to its content (`sizingOptions = .preferredContentSize`, not resizable) runs under the Dock once the content outgrows the screen: History did at 1025 pt on a 874 pt visible screen after "Value this week" went on top. Windows open at min(content, visibleFrame − margin), scroll, resize in height, and clamp a saved size; check with `ClaudeMeter --window-check` (v0.9.23).
- A replay starts from a blank state, so it learns caps the way a fresh install does: a first weekly cap taken at 5% (Oct 23: $142 from $7, the real cap ~$209) lingered because the blend only nudges a held cap at low %, and failed "This week" shares and weekly growth. The first weekly cap now waits for 10%. The live app never showed it (its cap carries over), so a replay FAIL can be a real cold-start bug, not aging data (v0.9.27).
- A signed-out CLI (Oct 24–26) leaves days with no probe readings, so the replay's real-data floors (openings, gate points, 5-hour growth) fail on any code; compare with a stash run on `main` before blaming a change (v0.9.28).
- The replay fed no cloud spend while the live meter counts it, so once most use moved to cloud sessions (Oct 25 on,
  ~$500–1000/day vs ~$25 on this Mac) it learned the caps from this Mac alone and failed accuracy, growth and the
  "This week" shares on a working meter. A test harness has to feed every input the live code reads (v0.9.32).
- Oct 29: one cloud session rose $77.65 in 4 minutes ("Research regional fishing limits") and Anthropic's 5-hour and weekly %
  never moved for it, so the "This week" shares ran 3 pts over the weekly card for a minute. The replay now fails only
  breaches lasting 5 minutes; if such rises repeat, find which sessions aren't charged to the plan (v0.9.34). Its
  History window count now starts at the later of the 7-day horizon and the replay's first reading.
- The weekly cap was the week's average spend per point, which lags when a point costs more as the week goes on (Oct 28–30: $2.2–2.7k against ~$3k from the climb, estimates 1.14× the readings, mostly Opus cloud sessions). It is now the larger of the average and the last day's climb; the larger, because the day's climb alone read low around an uncharged cloud rise and failed the "This week" shares (v0.9.35).
- NSStatusItem Preferred Position values on macOS 27 are not screen coordinates and can't be seeded reliably; only autosaveName plus a user ⌘-drag (v0.9.21).
