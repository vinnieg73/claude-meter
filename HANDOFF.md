# Claude Meter: handoff

Updated 2026-10-23 by Claude, from a background worker (v0.9.25: fixes from the 2026-10-23 audit, on branch
`fix/audit-2026-10-23`, not merged, not built, not installed).

## Status

v0.9.25 (build 38): every finding of `tool-reviews/2026-10-23/claude-meter.md` (0 High, 1 Medium, 4 Low), fixed in
the report's order on branch `fix/audit-2026-10-23` and pushed. Written on a Linux box with no Swift compiler: **not
compiled, not replayed, not rendered yet**. Run the Mac test plan below before merging or installing.
- Medium 1, cloud-opened windows never probed (Probe.swift, `Meter.takeFable`): `parseReset` read only "Oct 14 at
  3pm". It now also reads a time alone ("10:50pm (America/New_York)", the next time the clock reads it; up to 5
  minutes past counts as that one, since the report floors), month or day first with or without year/"at"/comma
  ("Oct 14, 2026 at 3:00 PM", "14 Oct 3pm"), "today/tonight/tomorrow at …", a weekday ("Wed at 3pm"), and a span
  ("in 4 hr 45 min", "in 4h 45m"), each with an optional zone (identifier or abbreviation). The report is parsed
  against the time it was asked for. The session line is found by its kind ("Current session …", whatever its
  parentheses say), and a session reset more than 5 h out is dropped, so a misread time can never let a probe open
  a window. No real "Current session" sample exists in the repo yet: see the plan.
- Low, "No separate Fable limit" after the weekly reset (`takeFable`): a report with no Fable line sets `fableNone`
  only if it lists another model's weekly limit ("Sonnet only"), no Fable reading was ever held, or the held one's
  week ended over a day ago (`cachedReportsFor`). Otherwise it clears `fableNone` and the card says "Waiting for a
  Fable reading." until a full report. Trade-off: a plan that really drops the limit says "waiting" for up to a day
  after its last Fable week ends.
- Low, probe answer dropped when a statusline reading lands mid-probe (`Meter.absorb`, `pick`, `markRestart`): a
  probe reading older than the held reading by at most 90 s (`slowProbe`), when the held one is from tap.json (not
  another probe), goes through `pick`. Being older, only a fall of 10+ points (`behindDrop`) counts as an early
  reset from it; a smaller fall keeps the statusline's newer number. An early reset is dated no later than the
  reading that saw it. Side effect: `lastExact.at` can step back by up to 90 s (the probe's launch time), and the
  history log can get a line slightly out of order (`exactHistory` sorts those in; replay sorts).
- Low, History can't be dragged taller after its page grows (HistoryView, HistoryChrome, App): the scrolling page
  reports its height (GeometryReader + `onChange(of:initial:)`, macOS 14) and `HistoryChrome.contentHeight` raises
  `contentMaxSize` to it (never lowers it). The window's own size isn't touched. Help is unchanged (static page).
- Low, Help's usage-report cadence (HelpView.swift Fable section, README sources table): now says every 5 minutes
  while Fable is in use here *or no 5-hour window is open*, every 30 otherwise.
- Skipped: nothing. Not touched: the Going cold open decision.
- Tests written (they run on the Mac): replay synthetic checks (section 6) for every parse form (24 cases through
  `parseReset`, 6 through the whole report into `sessionResets` and the probe gate, plus the >5 h and just-past
  guards), the Fable rollover (5 cases), and the overtaken probe (6 cases); `--window-check` gained a History growth
  line. Here, only a Python mirror of the new parser was run (scratch, not committed): 38 + 30 cases pass.
- A review of the diff (code-review skill; no Agent tool was available) found 10 items; fixed: a false early reset
  from an overtaken probe before a climb, `hadOne` measured from the wrong time, time-only resets read against the
  parse time, the max height being lowered, the growth check passing vacuously, a long array literal that might time
  out the type checker. Left: `lastExact.at` stepping back (above; it is the probe's real measurement time), two
  style items (a duplicate `group` helper that predates this, the max-height rule in two places).

### Mac test plan (audit 2026-10-23)

All in the background, nothing shown on Vinnie's screen (no `open` of windows; `--window-check` and `--render` build
windows without showing them). From `~/Code/Claude Meter`, on branch `fix/audit-2026-10-23`:
1. `swift build -c release 2>&1 | tail -20`: must compile with no errors. If it fails, the likeliest spots are the
   new code in `Probe.swift` (`parseReset` and helpers), `HistoryView.body` (`onChange(of:initial:)`), and the
   `forms` array in `Replay.swift` (split it if the type checker times out).
2. `./scripts/replay.sh`: section 6 must show no `FAIL: synthetic:` lines (its count goes from 12 to 61). The data
   FAILs from before (early resets, 5-hour and weekly growth) may still show; compare with the same run on `main`
   (`git stash; git checkout main; ./scripts/replay.sh; git checkout fix/audit-2026-10-23`): only new FAILs count.
3. `"$(swift build -c release --show-bin-path)/ClaudeMeter" --window-check; echo "exit $?"`: exit 0, both screens
   "fits", and the new line "History page S pt, grown T pt: opened with max S; rule S → T ok; after layout, rule X,
   live page Y ok". The first Mac run (2026-10-23) crashed here (exit 133) printing `Int(contentMaxSize.height)` when
   that height was AppKit's "unlimited" (greatestFiniteMagnitude); heights now print as "unlimited" instead. "rule"
   is read right after `contentHeight`, before any layout. "after layout" shows what a layout pass left: that run
   suggests the hosting view lifts a window's maximum to unlimited on layout, which would mean History's maximum
   never held in the live app either (so the audit's symptom may not happen there). "live page … ok" means the
   window can now go at least as tall as the grown page (a maximum of the page's height, or unlimited). Note the
   whole line in this file. If it says "DIDN'T GROW" while "rule … ok", the off-screen window may not run SwiftUI
   updates; then check once by hand on the real History window (open it right after install, before a weekly
   reading exists, and drag it taller once Value this week fills in).
4. `scripts/render-all.sh build/renders-audit-1023`: no failures; look at `help-light.png` / `help-dark.png` for the
   Fable section's new sentence (no other view changed).
5. Capture one real report: `claude -p /usage --model haiku --tools "" --strict-mcp-config --no-session-persistence
   --setting-sources "" --settings '{"disableAllHooks":true}' --output-format json` while a 5-hour window is open.
   Note the exact "Current session" line in this file (it was never captured). Then install
   (`scripts/build.sh --install`, background relaunch) and within ~5 minutes check
   `python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/Library/Application Support/ClaudeMeter/state.json"))).get("sessionResets"))'`
   prints a date: `sessionResets` must appear and match that line's reset. If it is missing, the line's
   wording is not one `parseReset` reads: add it to `Probe.swift` and to the replay forms.
6. After install, `ClaudeMeter --status`: version 0.9.25, a fresh probe reading, and a Fable line.

Deploy: only with Vinnie's typed go-ahead (merge `fix/audit-2026-10-23` into `main`, then `scripts/build.sh --install`).

v0.9.24 (build 37): shorter menu bar title, so Claude Meter fits beside the 58 pt Vitals dials (178.5 pt between the
notch edge at 848.5 and Vitals). Vinnie picked option 1 of three (via the coordinator): with the weekly % in the title,
the 5-hour % is left to the ring. Installed 2026-10-19 ~18:00Z; `--status` 0.9.24, weekly in title on, a reading 1m old.
Committed and pushed to `main` as 485a009 on 2026-10-19 ~19:35Z (Vinnie typed "Save commit and push").
- Title (`Meter.recompute`): week on → `<time> wk <week>` ("2h50m wk 41%", "cap 10:49 wk ~100%"); with no time part it
  keeps the 5-hour % ("34% wk 41%"). Week off → as before ("34% · 2h50m"). Cap time everywhere in the title is
  `Fmt.bareClock` (no AM/PM; always within 5 hours); `Fmt.clock` removed. One space before "wk" (was two).
- VoiceOver (`MenuBar.spoken`) says the 5-hour % first when the title leaves it out ("Claude usage, 34%, 2h50m, weekly 41%"). Not run:
  no CLI prints it.
- Measured on the real menu bar (`--status-log --status-test`, every test title; window width incl. padding):
  "cap 10:49 wk ~100%" 169 (was "~94% · cap 10:49 PM  wk ~100%" 242), "~100% · cap 10:49" 156, "4h59m wk ~100%" 150
  (was 210), "~94% · cap 10:49" 148, "2h50m wk 41%" / "1h10m wk ~42%" 142 (were 177 / 193), "31% · cap 10:49" 140,
  "~62% · 1h05m" 129, "8% · 4h52m" 113, "Claude" 81. Leftmost x 874 (widest form), all right of 848.5; Vitals held at
  window x 1043 throughout, so nothing went to the « overflow.
- Help's menu bar section: cap sample without PM, a new "2h50m wk 41%" sample, and the Weekly % setting line. README's
  top block and cap example match. Help rendered off screen (`--help-page`), icons sheet `build/renders-short/icons.png`.
- Replay: the same 3 data FAILs as before (early resets 0 vs 1, 5-hour growth 1.14×, weekly 0.61×); replay doesn't look
  at the title.
- `scripts/render-all.sh build/renders-short`: every fixture, History and Help, light and dark, rendered with no failures;
  the dropdown doesn't use the menu bar title, so it's unchanged.

v0.9.23 (build 36): "Value this week" in History, plus one line under the dropdown's weekly card. Installed 2026-10-19
~04:30Z; `--status` showed 0.9.23 and a probe reading 1m old (5h 4%, week 69%). Committed and pushed to `main` on
2026-10-19 ~13:00Z as "v0.9.23: Value this week in History; History and Help fit the screen" (Vinnie typed "Commit and push").
- Asked for by Vinnie via the coordinator; mockup option A: https://claude.ai/artifact/HDDp8xFFM5aW9RoCLEy7s7. If he
  picks option B (the receipt) instead, only `WeekValueSection.swift`'s body changes; the data (`WeekValue`) stays.
- What it shows (new `WeekValueSection.swift`, first module in `HistoryView`): "since <begin> · resets <reset>", the
  total at pay-as-you-go prices ("~" only when Elsewhere is in it), the multiple of the plan's week, a bar (this Mac
  dark gray, Elsewhere light gray, plan's week a blue tick; scaled to max(total, plan week)), a legend with the three
  amounts, a column per local day, and "By model on this Mac" (top 4, `Fmt.model` names). Empty state "No weekly
  reading yet." when there's no weekly window. `HistoryFootnote` gained one sentence (Elsewhere + the plan price).
- Data: `Meter.weekValue` in `recompute()` (stored as `Snapshot.weekValue`, copied to `History.value`). Range =
  `countsFrom(resets, week, restartedAt)` to now, the same as `fillWeekShares`. Elsewhere = `weekElsewhere` points ×
  `capWeek` / 100, nil when `weekElsewhere` is nil (under 2 points or no cap). The multiple is worked out in the views
  from `meter.plan`, so the History picker changes it at once. Prices: `Plan.monthlyPrice` (20/100/200) and
  `weeklyPrice` (× 12 / 52) in `History.swift`. Plan price shows whole dollars from $10 ("$46"), cents below ("$4.62").
- Dropdown: `WeekValueLine` in the weekly module after `ExtrasRows`: "Worth $312 so far · 6.8× your plan" and
  "History ›" (calls the same `openHistory` as the footer button; not click-tested on screen, by the no-windows rule).
  A shorter form ("$312 · 6.8× your plan") takes over if it can't fit. `long` fixture ("~$12.0k", 520×) stays 340 pt.
- Day columns, a decision: local days from the week start's day to the reset's day. A 3 PM reset touches 8 dates, so
  there are **8 columns** (Wed … Tue, Wed), not the brief's 7; the first and last are partial. With 7, Wednesday
  morning before the reset had no column (its spend lost, the wrong "Wed" bold). Help says the reset's weekday shows twice.
- Days are **this Mac only**. Elsewhere split per day from exact readings (weekly % × cap − this Mac's spend at each
  reading, differenced per day) went badly negative on real data (tested with a forced $40 elsewhere: Wed −$91,
  Sun −$11), so it was removed, as the brief allowed.
- Real numbers at 04:30Z Mon Oct 19 (week Wed Oct 14 3 PM → Wed Oct 21 3 PM): total $312, this Mac $312, Elsewhere none,
  6.8× Max 20x ($46/week). By model: Opus 5.5 $261, Sonnet 5.5 $31.93, Fable 5.1 $18.42, Haiku 5.5 $0.73. Days: Wed $148,
  Thu $0.47, Fri $45, Sat $75, Sun $43, Mon $0.45.
- Why Elsewhere is $0 this week: `capWeek` is $448 (it was $794 on Oct 17), and 69% × $448 ≈ $309 ≈ this Mac's $312.
  The cap is calibrated from readings that include cloud use, so cloud use shrinks the cap instead of showing up as
  Elsewhere (the known limit under Gotchas). The total is then "this Mac's spend", and real value elsewhere is missing.
- Help: a "Value this week" section after History, and a bullet in Weekly for the dropdown line. README's History
  paragraph mentions it. CLAUDE.md has the dated exception.
- Fixtures: popover calm, warn (with Elsewhere), critical, long (stress); History `fits` (with Elsewhere) and new
  `thismac` (no Elsewhere, early reset two days ago, so earlier days count for nothing); `uncalibrated` is the empty
  state. Renders (light and dark, every state) and `history-live.png` (installed app, real data, Max 20x) are in
  `build/renders-week-value/`. Fixture and debug-build renders read the plan from the dev binary's own defaults (Max 5x),
  so their multiples are 5x ones.
- Replay: the same 3 data FAILs on HEAD and on this tree (early resets 0 vs 1, 5-hour growth 1.55× → 1.54× from 6
  newer readings, weekly growth 0.59×). Replay doesn't check the value numbers. Re-run after the window fix: the same 3
  (1.55×, 0.60×) on newer data.
- Window fix, same v0.9.23 (Vinnie's screenshot, ~04:25Z): with Value this week on top, History's content is 1025 pt and
  his screen's visible height is 874 pt (1512×874 above a 75 pt Dock), and the window was sized to its content and not
  resizable, so Plan fit ran under the Dock. Now (`HistoryChrome.makeWindow`): History and Help scroll (`scrolls:`
  parameter; renders pass false), resize in height only (width fixed 560, content min 360, max = the natural height),
  open at min(content, visibleFrame − 8 pt margins) centred, keep a dragged size under autosave names
  "ClaudeMeterHistory" / "ClaudeMeterHelp", and clamp a saved frame that no longer fits (keeping its top edge). Help
  opens at 640 as before. No module changed.
- `ClaudeMeter --window-check` builds both windows without showing them and prints where each would open, on this
  screen and a 600 pt one. On his Mac: History 560×830 (window y 83–941, inside 75–949), Help 560×640; on 600 pt both
  560×556. A saved 1400 pt History half off screen (tested in the dev binary's own defaults, then deleted) opened at
  560×830 on screen. Not checked by eye: the window itself on his screen (no windows opened on it).

Before this: v0.9.22 (build 35): back to a status item that fits its text. Installed 2026-10-19 ~03:00Z; `--status` showed 0.9.22
and a probe reading 1m old.
- Why: Vinnie didn't like the fixed slot being longer than what it shows ("I want it to go back to the way it was,
  dynamically adjusting"). The `variableLength` item is back; MenuBar.swift, Meter.swift and HelpView.swift are as in
  v0.9.19 (the cap form shows the weekly % again). Kept: `autosaveName` "ClaudeMeter", `render` skipping snapshots that
  change nothing shown, tabular digits (width changes only when the character count does), `--status-log` /
  `--status-test`. CLAUDE.md's dated exception became a dated note.
- Checked: `--status-log --status-test` for 2 min: the button (and its window) is always the text's fitting width + 16 pt
  of the menu bar's own padding, e.g. "$0.42 today" 112, "8% · 4h52m" 113, "34% · 2h50m  wk 41%" 177,
  "~100% · 4h59m  wk ~100%" 209, "~100% · cap 10:49 AM  wk ~100%" 250. No blank slot. Replay: the same two data FAILs.
- Vitals (fixed 34 pt) sits to this item's right, so these width changes move the icons on its left, not Vitals.
  After install Vitals logged window x 1100.

Before this: v0.9.21 (build 34): a narrower fixed slot so Vitals fits. Installed 2026-10-19 ~01:14Z; `--status` showed 0.9.21 and a
probe reading 0m old (5h 13%, week 68%).
- Why: with v0.9.20's 234 pt slot, Vinnie couldn't see Vitals at all (screenshot): macOS's own overflow (the « at the
  notch, MenuBarAgent, not a third-party manager) took it.
- Fix: the slot is the time form with the weekly % ("~100% · 4h59m  wk ~100%") = **193 pt** on the real button
  (162 with weekly off). The cap form leaves the weekly % out so it fits ("~100% · cap 10:49 AM" = 162). Help's
  "Weekly % in menu bar" row says so. Dated exception in CLAUDE.md.
- `statusItem.autosaveName = "ClaudeMeter"`, so a ⌘-drag sticks across relaunches. No position seeding: on macOS 27
  "NSStatusItem Preferred Position" values aren't screen coordinates (probed: Vitals at 50–150 → x 1266, 200 → 1146,
  250–270 → 1108, 290–600 → 899 with this item saved at 354). Lesson in CLAUDE.md.
- Vinnie's defaults now hold ClaudeMeter = 354 and Vitals = 260 (set while probing), which keep Vitals right of this
  item. After a logged relaunch of both: this item x 899, window 209 wide (193 + padding), Vitals x 1108 (50 wide),
  50.5 pt free beside the notch (notch right edge 848.5 on the 1512 pt built-in display).
- `--status-log` now also prints the button window's x and width in screen coordinates.
- Replay: the same two data FAILs as before (early resets 2 vs 0; weekly growth 0.10×, 0.09× an hour ago on the
  same code), which don't touch the title.

Before this: v0.9.20 (build 33): the status item keeps one width. Installed 2026-10-19 ~00:52Z; after install `--status` showed
0.9.20 and a probe reading 0m old (5h 13%, week 67%). Asked for by Vinnie ("the constant moving in and out from behind
the notch is really annoying"); commit and push came as the coordinator's instruction.
- Bug: the item was `variableLength`, and the title changes width all the time ("~" on and off, 1–3 digit %, "12m" vs
  "1h05m", the cap form, "$0.42 today", "Claude" while loading). Each change re-laid out the menu bar, so icons near
  the notch slid in and out of view. Measured on an offscreen button (about 12 pt wider than the real one): 75 pt ("Claude") up to 245 pt (the cap form with weekly).
- Fix: `statusItem.length` is fixed at the widest title the meter can show with the current weekly setting
  (`MenuBar.fixedWidth`, measured on the real button: "~100% · cap <10:49 or 22:49 in the locale's clock>  wk ~100%"; "AM" is
  1 pt wider than "PM"). With weekly on that's **234 pt** on the real button. It's re-measured only when the weekly setting is toggled. The ring's image is
  widened on its left (`ring(lead:)`) to fill the slot, so ring + title sit at the right edge with the blank space on
  the left (a fixed-length button centres its content otherwise, which moved the ring about). Nothing shown changed.
- `render` skips snapshots that change nothing shown (title, % to 0.1, level). Side effect: a ring-centre change from
  a new menu bar height waits for the next title change (about a minute).
- Trade-off the coordinator picked (option A over shortening the cap text): about 45 pt blank on the left most of the time.
- Checked: `--status-log --status-test` (cycles 11 test titles every 2 s, the cap ones with the real clock format,
  AM and PM): every update length 234.0 / button 234.0 / fits 234.0 (1.8 min, 72 updates; the run before the AM fix, 2.6 min and 107 updates, was constant at 233). An earlier run with a typed
  "10:49 PM" fitted 235 (the real clock uses a narrow no-break space, U+202F), so the test titles now use `Fmt.clock`.
  `./scripts/replay.sh` gives the same two data FAILs on HEAD and on this tree (early resets 2 vs 0, weekly growth
  0.09×); replay doesn't touch the menu bar. No view changed, so no render-all.
- New flags `--status-log` / `--status-test` run the menu bar app; quit the installed one first (one meter at a time)
  and kill the test copy after, since it shows in the real menu bar.

Before this: v0.9.19 (build 32): real names for Remote Control sessions. Installed 2026-10-17 ~23:25Z, committed and pushed to `main` together with the unpushed v0.9.18 HANDOFF commit 560f467 (Vinnie typed "push and ship"). After install `--status` showed 0.9.19 and a probe reading 0m old (5h 81%, week 56%).
- Bug: Burning now and Going cold showed "Remote Control session (from a project)" for most Remote Control rows. That's the desktop app's placeholder title in its session record (`claude-code-sessions/*/local_*.json`); on 2026-10-17, 40 of 75 Remote Control records had it. v0.9.5 took any desktop title over the project, so the placeholder won.
- The real name (the project thread's title) is not on this Mac in any readable form. Searched for three placeholder sessions' thread titles and ids: the desktop records, the transcripts (wake envelopes carry only the thread id), `~/.claude.json`, `~/.claude/{sessions,state,session-env,cache,tasks,history.jsonl}` (`sessions/*.json` holds the same placeholder as `name`), `Application Support/Claude/{claude-code,config.json,ccd-ids.json,Local Storage}`, and `~/Library/Caches`. The only hits were thread ids inside the claude.ai web view's IndexedDB (Chromium leveldb, compressed; titles didn't grep), which is too fragile to read. The title lives on Claude's servers. The placeholder sessions also never call the thread status/label tools, so there are no headers to borrow. Their opening messages are mostly acks ("go with 1", "Commit freely"), so they're not used.
- Fix (`DesktopTitles.swift`, `LogIndex.sessionNames`): a title starting "Remote Control session" counts as no title. Order is now desktop title > `custom-title` > `agent-name` > the record's `postTurnSummary.status_detail` (the app's one-line summary of the last turn; first letter capitalised only when the first word is plain lowercase) > project. The summary is used only for placeholder-titled records. 33 of the 40 placeholder records have a summary; the rest show the folder, and the last-ran tag tells same-folder rows apart.
- Checked: a live off-screen render (`ClaudeMeter --render`, read-only) with the old installed build vs the new one: "Remote Control sessi…" ×2 and "Remote Control session (from a project)" became "claude-dashboard", "Waiting on cloud page…" and "NHL refresh + model rebuild done, HANDOFF pus…"; real titles ("Real session names in…", "MacBook bottlenecks and ideal config") unchanged. `./scripts/replay.sh` gives the same three data FAILs on HEAD and on this tree (History 26 of 27 windows, 5-hour growth 1.36×, weekly growth 0.11×); replay doesn't touch names. No view changed, so no render-all.
- Downside: a summary describes the last turn, so a row's name can change when a turn ends. If the desktop app starts saving real thread titles, they win automatically.
- CLAUDE.md has a dated exception for this.

### v0.9.18

v0.9.18 (build 31): the Max 20x retune. Installed 2026-10-17 ~07:05Z (the wait for the Oct 14 reset was overrun: the session stopped and nobody installed until Vinnie asked on Oct 17). Committed and pushed to `main` on 2026-10-17 (Vinnie typed "commit and push the 20x meter retune"). Plan setting set to `max20x` on 2026-10-17 ~20:45Z (Vinnie said "set the plan"; app quit, `defaults write`, relaunched, since `Meter.plan` is read once at launch).
- State at install: the old build had already relearned the weekly cap after the Oct 14 reset (no fake restart in the new week): `capWeek` $794, basisWeek 2. The basis bump will replace it with the next qualifying weekly reading. `cap5h` is $94, down from $278 on Oct 14; not looked into (cloud use the logs can't see pulls it down).
- Replay on Oct 17 history, old code vs v0.9.18: weekly ±0.49 → ±0.17, the "This week" shares FAIL (819 steps, Oct 12 to 15) gone, the fake early reset gone. Weekly growth reads 5.29× → -0.28× and still FAILs; with ±0.17 error and bias -0.05 that looks like the growth ratio summing tiny per-check moves (measured growth just over its 5-point floor), not a wrong cap. Inferred, not checked. 5-hour growth 1.46× FAILs the same in both.
- No written retune spec existed (the "Claude Meter workbench" thread never mentions 20x). Scope taken: fix what the Oct 11 upgrade to Max 20x left wrong. Plan fit's multipliers (Pro 1, Max 5x 5, Max 20x 20) are left alone: the measured 5-hour cap went from about $144 on 5x to $278 on 20x (about 1.9x, not 4x), but that is three days of data mixed with cloud use, not enough to override the official ratio.
- The bug: at 2026-10-12T17:48:31Z Claude Dashboard (`~/Code/Utilities/claude-dashboard`, `MeterLink.feed`) wrote tap.json with `source: "dashboard"`, weekly 50% (and a 5-hour 90% resetting two minutes later) while the week was at 59%. `absorb` treated every non-"tap" source as measured now, so the 9-point drop read as an early reset (`restartedAt` 17:47:23), and the week was counted from there: about $90 of local spend over 50 to 67% taught `capWeek` $150 (it was four figures). Replay showed it as weekly growth 1.53x and "This week" shares over the card on Oct 12 and 13.
- The fix: only `source == "probe"` is measured now; every tap.json reading (statusline or drop-in) counts like the statusline, raising a window or starting a later one, never lowering one (`Meter.absorb`, and `Replay` to match). A new `weekBasis` (3) relearns only the weekly cap: the next qualifying weekly reading replaces the bad $150 instead of blending from it. The 5-hour cap ($278) is kept.
- Replay after: weekly ±0.28 (was ±0.52), growth 0.96x (was 1.53x, FAIL), 4 early resets (was 5; the fake one is gone), the Oct 12/13 shares FAILs gone. Two FAILs remain, identical before and after the change: "This week" shares over the card on Oct 11 just after the upgrade (the 5x weekly cap, $948, applied to the first hours of 20x), and 5-hour growth 1.31x (5x caps carried into 20x windows, plus cloud use). My guess, not checked: both clear as Oct 11 ages out of the 8-day replay. The 5-hour one may not, since it already failed at 1.20 to 1.25x from v0.9.13 on, before most of the 20x data existed.
- Why install waits for 19:00Z Oct 14: the state still holds the fake `restartedAt` for the current week. Installed before the reset, the weekly basis bump would relearn from that same bad start and land at about $150 again. After the reset the new week has no restart, and the first weekly reading at 5%+ sets the cap.
- Plan fit side effect until about Oct 18: it uses the last 7 days of windows, and those before Oct 11 03:31Z were measured on 5x, so with the plan set to Max 20x their peaks are scaled 4x on the Max 5x row, overstating how often 5x would have capped.
- Also: the app's plan setting (`defaults read local.vinnie.ClaudeMeter plan`) was still `max5x`; set to `max20x` at install. Tomorrow's check (`~/.claude/scheduled-tasks/claude-meter-oct-15-check/SKILL.md`) now expects 20x caps and knows the dashboard row. README's tap.json row and a CLAUDE.md lesson cover the drop-in rule.
- Suggestion, not done: Claude Dashboard decides "newer" against tap.json, not the meter's state, so it can still write old numbers; the meter now ignores them as drops, but the dashboard could compare against `state.json`'s `lastExact`.

v0.9.17 (build 30), 2026-10-12, built, installed, and committed and pushed to `main` as 990e717 together with v0.9.16 (Vinnie typed "commit push"). On the live popover, Vinnie couldn't read Going cold: names were cut to "Re…". Changes:
- Going cold rows are now two lines (`ColdRow`): a 1 pt/unit sleeping mascot and the whole name with its tag, then, indented under the name, "[cold in 20m] then +$2.51 (+1.4%)". The separate family word ("Opus") is gone (the mascot colour says it; the model is in the tooltip), and "then" is back. The family-column hiding and the 90 pt tag cap from v0.9.16 are gone with it.
- The sleeping mascot colour is `ModelFamily.sleeping`: muted lifted 30% toward full, so the shut eyes read at 1 pt/unit on dark. Checked zoomed in the render.
- Burning now: a row's tag goes under its name as "Started Sun 9:32 PM" / "Last ran 4m ago" (the tooltip wording), so the name has the line; rows are centred on the mascot.
- New fixture `samename` (three "Remote Control session" cold rows tagged 39m/32m/27m in Opus, Sonnet and Haiku, two tagged burning rows), added to `render-all.sh`.
- Help's Going cold sample has "then" back; README and the CLAUDE.md exception updated.

v0.9.16 (build 29) went in with v0.9.17 (990e717). It adds the "Option C" mascots to the dropdown (mockup approved by Vinnie: https://claude.ai/artifact/Qnb3mzyTRLd2uD2QznCkVG). The menu bar is unchanged (still the ring). After install `--status` showed a probe reading 0m old (5h 17%, week 50%, Fable 18%). Replay gives exactly the same three data FAILs as committed v0.9.15 run on the same history (shares over the weekly card Oct 11, 5-hour growth 1.20x, 5-hour ±1.96), so nothing new. Renders of every state, light and dark, are in `build/renders/` (gitignored).

What v0.9.16 changes (uncommitted files: new `Sources/ClaudeMeter/Mascot.swift`; `App.swift`, `PopoverView.swift`, `WindowCard.swift`, `FableCard.swift`, `SessionsSection.swift`, `HelpView.swift`, `Meter.swift`, `Fixtures.swift`, `Resources/Info.plist`, `CLAUDE.md` (dated exception), `README.md`, this file):
- `Mascot.swift`: the worker band's sprite (16x10 units, same pixels as `~/.claude/mods/worker-band/hooks/sprites.ts`) drawn in a Canvas as one path, whole points per unit. Poses: run (run0/run1 every 500 ms, bobs up exactly 1 unit on run0, a unit of air reserved so rows never shift), still, asleep (eyes shut). `ModelFamily` by case-insensitive substring; colours are the brief's (Swarm Watch tokens), not sprites.ts's slightly different ones. Motion only while the dropdown is open (`PopoverState` set in `popoverWillShow`/`popoverDidClose`, passed as the `mascotsMove` environment value, default off so Help and renders are still) and never under Reduce Motion. Each running mascot is its own `TimelineView` ticking at 2 Hz, staggered 0.33 s.
- Header: the green "N active" pill is now a crew pill: a running mascot per Burning now session (five at most, then "+n") and "N working". N is `s.burning.count`, not `activeCount` (which is now unused in views).
- Cards: 5-hour window wears a gray still mascot (secondaryLabelColor); Weekly · all models three muted ones (Opus, Sonnet, Haiku); Weekly · Fable (and the no-limit Fable card, and any other "Weekly · X" card) one in the model's full colour. `MascotTitle.colors(for:)` picks them by title. WindowCard lost its `symbol` parameter.
- Burning now: no flame; each row starts with a 2 pt/unit running mascot (32x22 with bob air). The spend bar now starts after the mascot; a runaway's ⚠ column sits between mascot and name.
- Going cold: no snowflake; each row starts with an eyes-shut mascot in the muted colour, then the name, the family name in tertiary gray ("Fable"; nothing for an unknown model), the cold chip, and the cost. `Cooling` gained a `model` field (from the last turn). The word "then" before the cost was dropped (as in the mockup) because otherwise names were cut to 2 to 5 letters and the `long` fixture overflowed the popover width. The family column hides while any shown cold row has a "started 9:41 PM" tag (two cold rows sharing a name and idle time), else that row overflows; the `long` fixture now carries that tag on a cold row to keep this checked. In that worst case the name is squeezed to a sliver (whole name in the tooltip).
- (Superseded in v0.9.17: the Burning now tag cap and the Going cold family column described here were replaced by two-line layouts.)
- Help: a mascot sample line in Burning now (colours, bobbing, eyes shut, still labels); the Going cold sample matches the row (no snowflake, no "then").
- Fixtures: warn has a Fable burning session; cold rows have models (Fable, Opus, Haiku, Sonnet, unknown); `long` has 7 burning sessions so the header shows "+2".

Before v0.9.16: v0.9.15 (build 28) is committed and pushed to `main` (with Vinnie's go-ahead) and installed in `~/Applications` (2026-10-11 ~23:30 EDT). After install it read 6% / 47% against Claude's 7% / 47%. It fixes the meter missing a 5-hour window opened away from this Mac: on Oct 11 a cloud session opened one (Claude: "Session 4%, resets in 4 hr 45 min"), the meter's last reading's window had ended and nothing was logged here, so it said "No 5-hour window is open" and never probed; weekly sat at 45% against Claude's 47%. Now the usage report's "Current session … resets …" line is saved as `sessionResets` in `state.json`, and `windowOpen` counts that window as open when it ends later than the last reading's (two-minute margin as always). With no window known open, the report runs every 5 minutes (was 30) so such a window is found within about 5 minutes, and a report that reveals one triggers a probe right away. Replay: four new synthetic checks pass; the same three data FAILs as v0.9.14.

Before that: v0.9.14 (build 27) is committed and pushed to `main` (c813cc4, with Vinnie's go-ahead) and installed in `~/Applications` (2026-10-11 ~22:30). It adds the Fable card (the dated exception is in CLAUDE.md). It compiled cleanly, all 32 renders (a new `nofable` fixture) look right in light and dark, replay gives the same verdict as v0.9.13 on the same history (three data-driven FAILs, all from the cloud-heavy Oct 11 data: "This week" shares over the weekly card, 5-hour growth 1.22x, 5-hour ±1.93; the weekly-growth FAIL from the earlier handoff has cleared), and `--status` on the installed app showed "fable limit: 9% of its week, 0m ago" within a minute of launch. The repo's CLAUDE.md limits work to bug fixes; features need Vinnie's OK and a dated exception note there.

The "Claude Meter workbench" thread's 20x retune is this v0.9.18.

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

1. Oct 15: a scheduled read-only check re-runs replay after the Oct 7 early-reset data ages out.
2. Nov 4: a scheduled check confirms the weekly reset after DST ended.
3. Every Monday 9 AM: the weekly replay check reports PASS or FAIL. Scheduled tasks run while the Claude app is open, and a missed one runs at the next launch.

## Open decisions (Vinnie's)

- Value this week (v0.9.23): option A is built; option B (the receipt) only means rewriting `WeekValueSection`'s body.
  Day columns are 8 (a 3 PM reset touches 8 dates), not the brief's 7; the alternative is 7 24-hour slices labelled by
  the weekday each starts on. Elsewhere is usually $0 because the weekly cap absorbs cloud use (see Status), so the
  total is closer to a floor than the full value; fixing that means a cap calibrated only from Claude Code-only stretches,
  which was tried and rejected once (Gotchas).

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
- Cost of v0.9.15: the usage report now launches every 5 minutes whenever no window is known open (most of an idle night), about 3 seconds of CPU each.
- Use off this Mac (cloud sessions, claude.ai) shrinks the calibrated cap, because each reading divides local spend by a % that includes the other use. On Oct 10 it fell from about $198 to $76. The live % stays exact (a reading every minute). Burning now's %/hr and the estimate between readings run high on cloud days.
- Tried and rejected: skipping calibrations that imply a much smaller cap (to ignore cloud use). Estimates and the pace then grew only 0.5x as fast as the readings on cloud days, so "capped at" and the cap warning would come late. Replay's growth check fails.
- Tried and rejected: a 5-minute hold on the probe gate after a reset. It fails replay by blocking probes after real window openings.
- The 5-hour % weights turns by API list price (`Pricing.swift`). A new model id falls back to the newest price in its family. Update the table when models change.
- Desktop thread titles come from `~/Library/Application Support/Claude/claude-code-sessions/*/local_*.json`, an undocumented format. If it changes, rows quietly fall back to folder names.
- The app's Remote Control placeholder title is matched by prefix ("Remote Control session"). If the app changes that wording, the placeholder shows again; check one record's `title` first.
- Keep the folder at `~/Code/Claude Meter`. Scheduled checks and Claude Code history depend on that path.
