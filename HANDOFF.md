# Claude Meter: handoff

Updated 2026-11-04 by Claude. Version 1.0 (build 100) = the review-fix batch below, shipped on Vinnie's "version 1.0 yes, commit
push and ship please": committed, tagged v1.0, pushed and installed. Version naming now follows his rule: two numbers, build =
major × 100 + minor (next: 1.1 = build 101). The dated log is in `HANDOFF-HISTORY.md`.

## Review-fix batch (2026-11-04, from the Fable review; Vinnie: "i want all the fixes implemented")

Review notes: `/private/tmp/claude-501/-Users-vinnie-Code/1e96335e-ac88-4555-acc8-c5dc2d6778d4/scratchpad/claude-meter-review.md`.
All shipped in 1.0. `swift build`, `scripts/replay.sh` (PASS, 92 synthetic checks) and `scripts/render-all.sh build/renders-gray` run.

1. Replay: the 5-hour floors are waived once the plan's switch is seen (`Replay.floor5h`), so Ultra no longer FAILs.
2. Statusline tap: not broken, just never run. Claude Code 2.1.302 still sends `rate_limits` on stdin (the binary builds
   it from `five_hour`/`seven_day`, and a test run of the tap wrote tap.json). The desktop app never runs a statusline;
   only terminal sessions do (last one Oct 17). The footer now shows "statusline …" only while a reading is under 6 hours
   old; `--status` has a "statusline: last reading …" line.
3. Runaways and Going cold use the weekly cap with no 5-hour limit (runaway = 5% of the week in 30 minutes; the row says
   "+X% of week"). The footer's "not calibrated yet" goes by the weekly cap there too.
4. `weekly()` keeps the card (0%, estimated) after a reset with no cap learned.
5. Menus agree: the right-click menu hides "Weekly % in menu bar" in Ultra mode; the gear menu gained "Cloud sessions";
   `--status` says "weekly in title: always (no 5-hour limit)".
6. `refreshFable` (`claude -p /usage`) runs every 30 minutes, not 5, when there is no 5-hour limit. `PlanCredits.Reading.week`
   (the 15-minute usage read's `seven_day`) now feeds `reportWeek`, so a week climbing elsewhere still starts a probe.
7. Pricing: Sonnet 5.5 and the "sonnet" family cache reads are $0.20 (the claude-api docs, Nov 4). Fable 5 cache reads at
   $1.00 are confirmed (Fable 5.1 is $0.25).
8. A week under a day old holds today's pace (`Meter.youngWeek`): no cap time, no "cap" title, no History projection; the
   7-day average speaks alone. A synthetic check fails without it.
9. Ultra: History drops the 5-hour windows module, Plan fit drops the Capped and Busiest rows. Fixture `history-ultra`.
10. Grayscale first: `Theme.color` is gray (normal), primary (70%), red (90%); Fable card, runaway rows, Plan fit badges,
    verdict box, chips, cap lines, blue plan tick and the Usage bars are gray. Menu bar and ring: orange only for a real
    cap warning, red from 90% (`MenuBar.shown`). Mascots keep their colours (approved exception).
11. "Local session (from a project)" counts as untitled, so rows fall back to the summary, else the folder name.
12. Burning now's accessibility label says week or 5-hour window; Going cold says "(+X% of week)" / "(+X% of 5h)".
13. `tagSharedNames` reads a per-session first-turn cache (`firstTurnAt`, cleared whenever `turns` changes).
14. This file trimmed; the old log is in `HANDOFF-HISTORY.md`.
15. Version naming: done. Info.plist is 1.0 / build 100; tag `v1.0`. In the app it reads "Version 1.0".
- AM/PM: the title's run-out time says AM or PM (`Fmt.periodClock`). "~99% · cap Wed 10:49 AM" is 24 pt too wide, so
  `Fmt.fittingTitle` drops the word "cap" when the text passes 140 pt ("~99% · Wed 10:49 AM" fits).

## Ultra / no 5-hour limit (v0.9.35, live since 2026-10-31 13:56Z)

Anthropic renamed Max 20x to **Ultra** on 2026-10-30 ($200, "10x Pro every week", no 5-hour limit once the account is
verified; verification is automatic). Vinnie's account switched at 13:56Z on Oct 31. The meter switches by itself: two
usage reports (`/api/oauth/usage`, every 15 minutes) with no `session` limit set `fiveHourGoneSince`, one that lists it
clears it. Then: no 5-hour card, alerts or History windows; the title is the week ("41% · 3d4h"); burn %/hr is of the
week; probes run only within 10 minutes of use here or in the cloud, or when the report's week is above the last reading
(`Meter.windowOpen`). Readings are stamped `noFiveHourLimit: true` in history.jsonl and the replay follows those stamps.
The weekly cap is the larger of the week's average and `recentWeekCap` (spend over the last day per point gained).
`--status` prints "5-hour limit: none since …". Plans: Pro, Max, Ultra (raw values `max5x`, `max20x` unchanged).

## Next steps

1. Oct 15: a scheduled read-only check re-runs replay after the Oct 7 early-reset data ages out.
2. Nov 4: a scheduled check confirms the weekly reset after DST ended.
3. Every Monday 9 AM: the weekly replay check reports PASS or FAIL. Scheduled tasks run while the Claude app is open, and a missed one runs at the next launch.

## Open decisions (Vinnie's)

- Value this week (v0.9.23): option A is built; option B (the receipt) only means rewriting `WeekValueSection`'s body.
  Day columns are 8 (a 3 PM reset touches 8 dates), not the brief's 7; the alternative is 7 24-hour slices labelled by
  the weekday each starts on. Elsewhere was usually $0 because the weekly cap absorbed cloud use; v0.9.26 counts the
  cloud sessions exactly and in the cap, so "Other" is what's left (claude.ai chat, the phone, other computers) and
  can still be absorbed by the cap the same way.

- Mascots (v0.9.16): commit and push v0.9.16 (his typed words). Read "keep the model name text" in Burning now as keeping the model in the row's tooltip (moved there in v0.9.6 at Vinnie's request), not adding it back inline as the mockup shows; say if it should be inline. Help's section headers still wear the flame and snowflake, and its Burning now sample row has no mascot; left as is. Going cold names get about 70 pt now (was about 110) because of the mascot and family column.

- Fable (v0.9.14): whether the Fable limit should notify at 80% and 95% like the other two (it blocks Fable when it fills; today it only shows). Whether to also use the usage report's 5-hour and weekly numbers: it is a free reading that never opens a window, which the probe can't offer with no window open (the "Known limit" below), but it prints whole percents and the probe gives `unifiedWindows` fractions, so it was left out of calibration for now.

- From the 2026-10-11 audit, not done in v0.9.13:
  - Medium 1, Going cold never lists 5-minute-cache sessions: Help says so on purpose ("already cold by then"). Listing them means showing a session in Burning now and Going cold at once, or a shorter idle bar for that tier. Your call.
  - Cache tier from any 1h write (prior #9): kept as decided in v0.9.11.
  - Display and wording: a stale card still reading "exact"; Plan fit verdict wording, "Capped: never" and "Busiest 0%" when uncalibrated, "Exact readings logged since"; a one-day weekly average labelled an average; 99.6 printed "100%"; "~210% by reset" past the 150% pace line; the weekly project row's 0%; the open window bar past the plot edge; informational footer notices in red; the ring dot angle.
  - Behaviour choices: Sync dropped while a probe runs; the probe-failure footer while tap readings flow; the stalled alert re-firing after 8 days, or right after wake; the weekly chart's shape before an early reset when little or nothing was logged here.
  - Plausible, not confirmed, left alone: a held window ended early with no later message; sign-out seen only on stderr, and any "login"/"expired" error text; the runaway title placeholder; per-model rows carried over; a title line after a cut-short line; the 7-day average with a reset after the last reading. nvm searches only the newest version (known).
- Audit leftovers: the 12 'skip' items in `claude-meter-open-findings-2026-10-11`, plus replay's drawn-vs-group window counting at the 7-day edge (#23, second half).

## Gotchas

- Weekly growth read 0.75× on Oct 25 but isn't judged until the checks' measured growth reaches 5 points: the likely
  next replay drift FAIL once this week climbs (the same small-numbers effect as Oct 17). Look at it before
  touching the cap.
- On Oct 25 the running ClaudeMeter (pid 37921) had started Oct 23 04:33, before the v0.9.26 binary was installed
  (Oct 25 21:32), and no `cloud.json` existed: the cloud feed wasn't running. Quit and reopen the app (Vinnie's call).
- Cloud sessions (v0.9.26): the sessions list is an unofficial API (`anthropic-beta: ccr-byoc-2025-07-29`); if it
  changes or breaks, the feed goes quiet ("error" in `--status`), the ledger keeps what it had, and the numbers fall back
  to this Mac + Other as the days pass. Only the 50 newest rows of each listing are read, so a session that drops off
  and is resumed later is re-based from its stored cost (kept 60 days), not booked whole. `cost_usd` is taken as priced
  like `Pricing.swift` (API list price); not checked. A Remote Control session on another Mac with the same folder path
  under the same home would be taken for this Mac's (not counted). `rcChild` is a reconciliation stub, counted nowhere.
- The keychain prompt (if any) names the binary that asks: the dev build in `.build/` and the installed app each may
  ask once. The token is never written; `cloud.json` holds titles, costs, times, models and folders only.

- Mascots: `--render` draws them still (motion is off outside the open dropdown), so a bob problem won't show in renders. To check it, temporarily flip `MascotsMoveKey.defaultValue` to true and render. Reduce Motion can only be checked on the real app.

- The Fable reading comes from `claude -p /usage`, parsed as text ("Current week (Fable): 9% used · resets Oct 14 at 2:59pm (America/New_York)"). A wording change in Claude Code would stop it quietly: the card would read "Waiting for a Fable reading." and `--status` "fable limit: not read yet" or an old reading. Check `Probe.usageLine` and `parseReset` first then. The report sometimes prints the Fable reset floored to the minute (2:59pm); the meter snaps it to the weekly window's reset when within 15 minutes.
- The usage report is a local command: `claude -p /usage` makes no model request (the result shows `total_cost_usd` 0, `num_turns` 0, `duration_api_ms` 0) and does not open a 5-hour window, so `refreshFable` is not behind the probe gate at all: it launches claude every 30 minutes while the app runs (every 5 with Fable in use here or no 5-hour window known to be open), about 3 seconds of CPU each time.
- A second-opinion review of the v0.9.14 diff found six issues (a Fable line whose reset couldn't be read showed "no separate limit"; a report without the Fable line wiped a good reading; the window gate; the retry backoff never binding; the year guess at a year's turn; future-dated `fable` fields on a clock set back). All six are fixed in the installed build.

- Before calling anything done, run `./scripts/replay.sh` (must PASS). For view changes, also run `scripts/render-all.sh <dir>` and check light and dark. Replay doesn't exercise `Probe.swift`, so after an install confirm `ClaudeMeter --status` shows a fresh probe reading.
- `scripts/build.sh --install` kills and relaunches the menu bar app. A plain `build.sh` only writes `build/`.
- Releases bump `Resources/Info.plist` (version and build) and use `vX.Y.Z: …` commit messages.
- Vinnie's Mac needs his own typed go-ahead for each commit and push.
- The Oct 15 check's cap ranges were updated for v0.9.7's lower caps (about $144 / $1.1k). If caps move again, update `~/.claude/scheduled-tasks/claude-meter-oct-15-check`.
- Known limit (narrowed in v0.9.15): with no 5-hour window open by this Mac's reckoning AND the usage report listing none, the meter can't probe, because a probe would open a window. A window opened elsewhere is now found by the report within about 5 minutes (sooner on Sync, which reads the report and probes once it answers).
- v0.9.15 trusts `claude -p /usage` not to open a window: the probe gate now opens on its session line. A wording change fails safe (an unread reset is nil, and nil means no window; since v0.9.25 a session reset over 5 h out is dropped too). But the "no window opened" claim rests on the report showing `total_cost_usd` 0 and `duration_api_ms` 0, not on a test run with no window open. If a future Claude Code made `/usage` a model request, it would itself open windows; check that first if windows start opening with no use.
- Cost of v0.9.15: the usage report launches every 5 minutes whenever no window is known open (most of an idle night), about 3 seconds of CPU each. Not in Ultra mode since the next batch: every 30 minutes there.
- Use off this Mac (cloud sessions, claude.ai) shrinks the calibrated cap, because each reading divides local spend by a % that includes the other use. On Oct 10 it fell from about $198 to $76. The live % stays exact (a reading every minute). Burning now's %/hr and the estimate between readings run high on cloud days.
- Tried and rejected: skipping calibrations that imply a much smaller cap (to ignore cloud use). Estimates and the pace then grew only 0.5x as fast as the readings on cloud days, so "capped at" and the cap warning would come late. Replay's growth check fails.
- Tried and rejected: a 5-minute hold on the probe gate after a reset. It fails replay by blocking probes after real window openings.
- The 5-hour % weights turns by API list price (`Pricing.swift`). A new model id falls back to the newest price in its family. Update the table when models change.
- Desktop thread titles come from `~/Library/Application Support/Claude/claude-code-sessions/*/local_*.json`, an undocumented format. If it changes, rows quietly fall back to folder names.
- The app's placeholder titles ("Remote Control session (from a project)", "Local session (from a project)") are matched by prefix or suffix (`DesktopTitles.isPlaceholder`). If the app changes that wording, the placeholder shows again; check one record's `title` first.
- Keep the folder at `~/Code/Claude Meter`. Scheduled checks and Claude Code history depend on that path.
