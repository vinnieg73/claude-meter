# Claude Meter: handoff

Updated 2026-10-11 (late evening) by Claude, from the Utilities project thread "Fable usage in Claude Meter" (v0.9.14, uncommitted on `main`).

## Status

v0.9.14 (build 27) is built and installed in `~/Applications` (2026-10-11 ~22:20) but NOT committed or pushed: Vinnie's own typed go-ahead is needed for both. It adds the Fable card (the dated exception is in CLAUDE.md). It compiled cleanly, all 32 renders (a new `nofable` fixture) look right in light and dark, replay gives the same verdict as v0.9.13 on the same history (three data-driven FAILs, all from the cloud-heavy Oct 11 data: "This week" shares over the weekly card, 5-hour growth 1.22x, 5-hour ±1.93; the weekly-growth FAIL from the earlier handoff has cleared), and `--status` on the installed app showed "fable limit: 9% of its week, 0m ago" within a minute of launch. The repo's CLAUDE.md limits work to bug fixes; features need Vinnie's OK and a dated exception note there.

Another thread, "Claude Meter workbench", also works on this app (a 20x retune due around Oct 14). Pull before starting and keep changes separate.

## Done recently

- v0.9.14: the Fable card (asked for by Vinnie 2026-10-11). What was found first:
  - The probe's `rate_limit_event` carries no Fable window today. It did Sep 25–30, 2026 (246 readings, every one at 0%, key `seven_day_fable`, filed as "Weekly · Fable" in `extras`), and none since. The Claude Code binary (2.1.293) knows `seven_day_opus`, `seven_day_sonnet`, `seven_day_overage_included` and a `model_scoped` array for the statusline, described as "additive: absent when … served from cached data", so the tap can't be relied on for it either (GitHub anthropics/claude-code#88137 asks for `seven_day_fable` there).
  - Anthropic's support article "Using Claude Code with your Pro or Max plan" says "Max plans also have a separate weekly limit for Fable." `claude -p /usage --output-format json` prints it: "Current week (Fable): 9% used · resets Oct 14 at 2:59pm (America/New_York)", as a local command (`total_cost_usd` 0, `duration_api_ms` 0): no model request, so it costs nothing and never opens a 5-hour window.
  - The logs have Fable turns (`claude-fable-5-1`), already priced in `Pricing.swift` ($10 / $50 per M, cache reads $0.25).
  What was built:
  - `Probe.launch(_:)` runs claude with any arguments (the Haiku turn and the usage report share it, same env and timeout); `Probe.usage()` parses the report's "Current … : N% used · resets …" lines (`parseUsageText`, `parseReset`). A report with limits but no Fable line = a plan without one; no limit lines at all = a failure, never "no limit".
  - `Meter.refreshFable` runs from `sync()`, not behind the probe's window gate (the report opens no window): every 5 minutes with a Fable turn in the last 15 minutes, every 30 otherwise, at once when the held reading's week has ended, and on Sync; failures back off a minute doubling to 30, and the retry time alone decides the next try. The reading is `state.fable` (a `Window`) with `state.fableChecked` (last report read) and `state.fableNone` (last report that listed limits but no Fable line); nothing goes to `history.jsonl`. A report without the Fable line never wipes a reading still in its week (Claude Code's cached answers leave the per-model limits out). The Fable reset is snapped to the weekly window's when within 15 minutes, and the window's stands in when the text can't be read (the report floors the Fable week to "2:59pm" while the all-models week says "3pm").
  - If the probe ever reports `seven_day_fable` again, `absorb` takes it as the Fable reading too, and `ExtrasRows` hides the Fable row so it isn't shown twice.
  - `FableCard` (new file): the Fable limit as a `WindowCard` with `tint: Theme.fable` (pink) and the `sparkles` symbol; orange/red still take over at 70/90. Under it "This Mac: ~3% of the 5-hour window · ~1% of the week ($6.20)": this Mac's Fable spend as points of each overall window (spend ÷ calibrated cap), "$ · tok this week" before calibration, "no Fable use this week" when the limit has a number but this Mac added nothing. With no limit: "No separate Fable limit on your plan. Fable counts toward the limits above." The card shows when a limit is known for the week or Fable was used here this week.
  - `Turn.fable` (derived, not cached), `Burn.fable`: a Fable session's bar in Burning now is pink. `Theme.fable = .pink` is used nowhere else.
  - Help: a Fable section after Weekly; Notifications and Sources bullets updated. README: dropdown bullet, sources table row, a "Usage report" subsection. `--status` prints the Fable line. Fixtures: calm (7%), warn (74%), critical (92%), idle (0%, no local use), `nofable`.
  - Not done, on purpose: no 80%/95% notifications for the Fable limit (not asked for; Help says so); no Fable estimate between readings (the exact number is shown as of its reading, so no Fable cap is calibrated); nothing in History or Plan fit; the report's 5-hour and weekly numbers are not used as readings.
- v0.9.13 (branch `fix/audit-2026-10-11`, from the audit `tool-reviews/2026-10-11/claude-meter.md` in project files):
  - Medium: the pace projection (5-hour and weekly), the 5-hour chart and History's peak count from an early reset (`restartedAt`), not from the window's start.
  - Medium: a window that lapsed since the last reading is `stale`, so it raises no 80%/95%/cap alert until a reading measures it.
  - Medium: History extends a window at its own rate only from 10% and $0.50 behind it (calibration's minimums), else today's cap.
  - Medium: the probe gate keeps two minutes clear of a walked window's reset, and of the window a message is in when there is no reading.
  - Medium: the statusline tap writes only a newer number (a climb, or a later window), so a second, idle session can't stamp older numbers fresh.
  - Lows: probes run with nothing logged on this Mac while the last reading's window is open (cloud-only use); alerts by the rounded %, one banner when a jump crosses 80 and 95; "cap in ~<1m"; the no-window notice clears as soon as a window is open; a future-dated tap doesn't set tapSeen; `--status` age never negative; the tap can't crash on a huge % and colours by the rounded %; Bedrock-prefixed ids and claude-3-sonnet priced right; a failed login-shell launch is retried, not cached as unset; a failed index-cache write stays dirty; Desktop title ties go by path; uninstall.sh honours CLAUDE_CONFIG_DIR and a bare `claude-meter-tap`; render flags without --render print usage; Help's Burning now mentions the 50¢/hr floor; the "fits" fixture's open window is open.
  - Replay: the tap's later-window early resets are expected like the meter takes them; each floor is at least one; new synthetic checks (early-reset pace and chart, lapsed windows stale with no alert, the walked-window probe margin, probing with nothing logged).
  - Not done (see Open decisions): Medium 1 (Going cold for the 5-minute cache) and the product/display Lows.
- v0.9.12: 9 of the 12 'skip' findings:
  - the menu bar cap shows the time only
  - a late copy marks a turn fast
  - old model ids priced right
  - a reset alert held until notifications are allowed
  - the shortcut message gets its own slot
  - legacy cache marks re-read once
  - coverage moves with discovery
  - no folders created by read-only runs
  - replay floors scaled for short histories

  Replay's weekly growth check fails at 0.87x on today's data, identically on v0.9.11: cloud work raises the weekly % with no local spend.
- v0.9.11: the new "Night Shift" app icon (design in `design/icon-night-shift/`, drawn by `scripts/make-icon.swift`). It also fixes 22 of the 26 open findings in `claude-meter-open-findings-2026-10-11` (project files). Not done, on purpose:
  - #9 (Going cold tier): one session in a day mixed 5m and 1h cache writes, and the new rule would have hidden it.
  - #17 (probe child leak): no orphaned probe processes after hours of once-a-minute probing, so it isn't real.
  - #19 (SIGTERM): tested, and children don't inherit the ignored signal.
  - #24 (uninstall): removing the whole tap statusLine block is correct.
  - #23's window-count half was left.
- v0.9.10: 10 fixes from the Oct 10 swarm audit (report `claude-meter-swarm-audit-2026-10-10` in project files):
  - cache writes from per-step usage
  - `state.json` never overwritten after a read error
  - replay's unbacked-alert check, turn times and coverage
  - relaunch while the old copy is still quitting
  - colour follows the rounded %
  - two early-reset gaps
  - retry wait after a sign-out
  - plan-fit verdict

  History now extends past windows at their own rate instead of today's cap.
- v0.9.9: the probe runs once a minute whenever a 5-hour window is open, local activity or not, so readings are never more than about a minute old while a window is open.
- v0.9.8: while a 5-hour window is open, the meter probes every 5 minutes even if nothing is logged on this Mac. Before, it only probed after local activity, so usage from cloud sessions, claude.ai or the phone left it stuck (on Oct 10 it showed 25% while the real number was 45 to 51%).
- v0.9.8: one notification when exact readings stop. It fires after an hour of Claude Code use since the last reading with none arriving, and quotes the probe's last error. Replaying a week of history: 0 false alarms. It doesn't fire on the first message after a break, since a reading follows within a minute. An hour of use while the meter was quit doesn't count. A simulated 2-hour outage in replay fired it exactly once; never seen firing for real yet.
- A weekly read-only replay check runs Mondays at 9 AM (scheduled task `claude-meter-weekly-replay`, in the desktop app's Scheduled sidebar).
- v0.9.7: 12 audit fixes. Sonnet 5.5 cache reads at $0.10. Fast mode only on Opus 5.5, Opus 5 and Opus 4.8. The probe strips API, Bedrock, Vertex and Foundry env vars, merges rate_limit_events, and catches expired-token sign-outs. The `CLAUDE_CONFIG_DIR` lookup runs off the main thread with 3 retries. A runaway's row is pinned in Burning now. The week chart scales correctly around an early reset. Replay is stricter and anchored to the newest reading.
- v0.9.6: the model moved to the row tooltip so names fit. Tags read "· 4m". "cold in <1m".
- v0.9.5: rows are named by the desktop app's thread title. Rows that share a name get a last-ran tag.
- Replay: the weekly accuracy floor scales with how many days the week's readings span.

## Next steps

1. Commit and push v0.9.14 once Vinnie gives the word (the diff is in the working tree on `main`; the version and build are already bumped).
2. Oct 15: a scheduled read-only check re-runs replay after the Oct 7 early-reset data ages out.
3. Nov 4: a scheduled check confirms the weekly reset after DST ended.
4. Every Monday 9 AM: the weekly replay check reports PASS or FAIL. Scheduled tasks run while the Claude app is open, and a missed one runs at the next launch.

## Open decisions (Vinnie's)

- Fable (v0.9.14): whether the Fable limit should notify at 80% and 95% like the other two (it blocks Fable when it fills; today it only shows). Whether to also use the usage report's 5-hour and weekly numbers: it is a free reading that never opens a window, which the probe can't offer with no window open (the "Known limit" below), but it prints whole percents and the probe gives `unifiedWindows` fractions, so it was left out of calibration for now.

- From the 2026-10-11 audit, not done in v0.9.13:
  - Medium 1, Going cold never lists 5-minute-cache sessions: Help says so on purpose ("already cold by then"). Listing them means showing a session in Burning now and Going cold at once, or a shorter idle bar for that tier. Your call.
  - Cache tier from any 1h write (prior #9): kept as decided in v0.9.11.
  - Display and wording: a stale card still reading "exact"; Plan fit verdict wording, "Capped: never" and "Busiest 0%" when uncalibrated, "Exact readings logged since"; a one-day weekly average labelled an average; 99.6 printed "100%"; "~210% by reset" past the 150% pace line; the weekly project row's 0%; the open window bar past the plot edge; informational footer notices in red; the ring dot angle.
  - Behaviour choices: Sync dropped while a probe runs; the probe-failure footer while tap readings flow; the stalled alert re-firing after 8 days, or right after wake; the weekly chart's shape before an early reset when little or nothing was logged here.
  - Plausible, not confirmed, left alone: a held window ended early with no later message; sign-out seen only on stderr, and any "login"/"expired" error text; the runaway title placeholder; per-model rows carried over; a title line after a cut-short line; the 7-day average with a reset after the last reading. nvm searches only the newest version (known).
- Audit leftovers: the 12 'skip' items in `claude-meter-open-findings-2026-10-11`, plus replay's drawn-vs-group window counting at the 7-day edge (#23, second half).

## Gotchas

- The Fable reading comes from `claude -p /usage`, parsed as text ("Current week (Fable): 9% used · resets Oct 14 at 2:59pm (America/New_York)"). A wording change in Claude Code would stop it quietly: the card would read "Waiting for a Fable reading." and `--status` "fable limit: not read yet" or an old reading. Check `Probe.usageLine` and `parseReset` first then. The report sometimes prints the Fable reset floored to the minute (2:59pm); the meter snaps it to the weekly window's reset when within 15 minutes.
- The usage report is a local command: `claude -p /usage` makes no model request (the result shows `total_cost_usd` 0, `num_turns` 0, `duration_api_ms` 0) and does not open a 5-hour window, so `refreshFable` is not behind the probe gate at all: it launches claude every 30 minutes while the app runs (every 5 with Fable in use here), about 3 seconds of CPU each time.
- A second-opinion review of the v0.9.14 diff found six issues (a Fable line whose reset couldn't be read showed "no separate limit"; a report without the Fable line wiped a good reading; the window gate; the retry backoff never binding; the year guess at a year's turn; future-dated `fable` fields on a clock set back). All six are fixed in the installed build.

- Before calling anything done, run `./scripts/replay.sh` (must PASS). For view changes, also run `scripts/render-all.sh <dir>` and check light and dark. Replay doesn't exercise `Probe.swift`, so after an install confirm `ClaudeMeter --status` shows a fresh probe reading.
- `scripts/build.sh --install` kills and relaunches the menu bar app. A plain `build.sh` only writes `build/`.
- Releases bump `Resources/Info.plist` (version and build) and use `vX.Y.Z: …` commit messages.
- Vinnie's Mac needs his own typed go-ahead for each commit and push.
- The Oct 15 check's cap ranges were updated for v0.9.7's lower caps (about $144 / $1.1k). If caps move again, update `~/.claude/scheduled-tasks/claude-meter-oct-15-check`.
- Known limit: with no 5-hour window open by this Mac's reckoning (the last reading's window ended and nothing was logged here since), the meter can't probe, because a probe would open a window. Use elsewhere then shows up only at the next message on this Mac (Sync won't probe either, for the same reason).
- Use off this Mac (cloud sessions, claude.ai) shrinks the calibrated cap, because each reading divides local spend by a % that includes the other use. On Oct 10 it fell from about $198 to $76. The live % stays exact (a reading every minute). Burning now's %/hr and the estimate between readings run high on cloud days.
- Tried and rejected: skipping calibrations that imply a much smaller cap (to ignore cloud use). Estimates and the pace then grew only 0.5x as fast as the readings on cloud days, so "capped at" and the cap warning would come late. Replay's growth check fails.
- Tried and rejected: a 5-minute hold on the probe gate after a reset. It fails replay by blocking probes after real window openings.
- The 5-hour % weights turns by API list price (`Pricing.swift`). A new model id falls back to the newest price in its family. Update the table when models change.
- Desktop thread titles come from `~/Library/Application Support/Claude/claude-code-sessions/*/local_*.json`, an undocumented format. If it changes, rows quietly fall back to folder names.
- Keep the folder at `~/Code/Claude Meter`. Scheduled checks and Claude Code history depend on that path.
