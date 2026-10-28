# Claude Meter: handoff

Updated 2026-10-28 by Claude (v0.9.32: Usage / Credits tabs, and the replay fixed to PASS. Committed, pushed to
`main` and installed ~21:25Z on Vinnie's typed "commit push and ship then". Ask him for a screenshot of each tab.)

## Status

v0.9.32 (build 45): **dropdown tabs**. Vinnie (with a screenshot of the scrolling dropdown): "move everything that has
to do with API credits to its own tab in the drop down. there will be 2 tabs at the top". Read as both credit cards.
- `DropdownTabs` in `PopoverView.swift`: a custom two-segment bar (Usage | Credits) under the header, kept in the
  `dropdownTab` default. Custom rather than a segmented Picker so Credits can carry a red dot (only while Usage is open
  and `CreditsView.alarm` or `planCredits.limitReached`). Credits tab: Usage credits card, API credits card, or a
  `NoCreditsNote` with Set up (opens the editor) when no balance is typed. `capToScreen` scrolling kept as a backstop.
- Fixtures: `tab` field; the credits fixtures render the Credits tab; new `creditsalert` (Usage tab, red dot) and
  `nocredits`. Help, README, CLAUDE.md updated. Renders in `build/renders-tabs/` checked light and dark.
- Replay fixed (Vinnie: "can we fix them first??"). The 4 FAILs (shares, 14 gate points, 5-hour growth 0.87×,
  accuracy ±2.14) failed identically on v0.9.31: the replay fed NO cloud spend (`cloudSpend` stayed empty) while the
  live meter counts it, and since Oct 25 most use is cloud (~$500–1000/day vs ~$25 here). Two harness changes, no
  meter code: (1) each step gets cloud.json's ledger as a feed running all along would have booked it (entry whole
  once `at` passed, before that its span's elapsed part); `seen`-based was worse (lumps at the first read Oct 26);
  (2) the gate-shut check also runs after resets whose next window opened away from this Mac >1 min later (half
  strength: no gate-opens check). Now PASS: 5-hour ±1.02 / 1.05×, weekly ±0.39 / 0.92× (close to the 0.88 edge),
  19 gate points. Live `--status`: caps 5h $582, week $2.1k; accuracy ±0.5 (5h) and ±0.4 (weekly) over 20 checks.
  The replay binary is unbundled, so it can't see the app's settings; it reads cloud.json whatever the setting.
- Checked: release build OK; `scripts/render-all.sh build/renders-0932` OK, all 38 dropdown renders 680 px wide
  (`long` 1790, `critical` 1850). Unchecked (renders can't show it): the live popover resizing on a tab switch, and
  Set up opening the dialog from inside the popover (the `editingCredits` path). Ask Vinnie for screenshots after install.
- Note: Vinnie's live Usage credits card is red (limit reached, $42.08 of $40), so the dot will be on all month.

v0.9.30 (build 43), part 1: **Usage credits card** (claude.ai extra usage). Vinnie: "yes i mean both of them" (both
claude.ai usage credits and Console API credits).
- Read with the Claude Code sign-in (`Credentials`, as the cloud feed): `GET /api/oauth/usage` → `extra_usage`
  (`used_credits`, `monthly_limit` in minor units with `decimal_places`, `spend_limit_reached`, `is_enabled`,
  `credits_ever_enabled`) and `GET /api/oauth/organizations/<org>/prepaid/credits` → `amount` (cents). Both found in
  Claude Code's own binary (its /usage reads them). `PlanCredits` in `Credits.swift`, polled every 15 min from
  `CreditsFeed.tickPlan`, saved as `planCreditsRead`. Shown once extra usage was ever on or a balance is there.
- `--extra-check` against the real account (2026-10-28 ~00:00Z): extra usage $42.08 of $40.00 monthly limit,
  spend_limit_reached true, is_enabled false (disabled_reason org_level_disabled_until); prepaid balance $0.
- Card: "$42.08 of $40.00 this month", "balance $0.00", a bar (red at the limit), "Monthly limit reached. Extra
  usage is off." in red. No reset date in the response, so none shown.
- **The dropdown now scrolls** (`PopoverView.capToScreen`, live app only): the modules cap at the screen's visible
  height − 130 pt; header and footer stay. With both cards the `long` stress case is ~1085 pt vs ~945 pt on his
  14" screen (`critical` alone was 895). Checked in a temporary render: cap 600 → modules 600 pt, a big cap or none →
  natural height (ScrollView reports its content's height). Renders still draw everything (cap off).
- Also: an invisible Edit main menu (⌘V/⌘C/⌘A/⌘Z in the credits dialog), and `editingCredits` so closing the
  dropdown doesn't hide the app under the dialog.
- Replay 2026-10-28: the same 3 FAILs on this tree and on unchanged `main` (stash run): This week shares 85 steps,
  14 gate points, 5-hour accuracy ±2.01.

Part 2: **API credits card** for the Console's prepaid credits (Vinnie: "get the usage credit tracker
included in the claude meter"; read as the Console API credits that fund Parlay Builder, ~$137 left of $146.88,
expires Nov 14). Mockup: https://claude.ai/artifact/2G5n3LjuH6XWtyBfmZhVBt (A live, B running low, C typed in).
- No API returns the prepaid balance (checked the Usage and Cost API docs 2026-10-27). So the balance is TYPED IN
  (gear or right-click → API credits…, an NSAlert with left / granted / expires) and is the anchor. With a key in the
  keychain item `Claude Meter Console key`, `CreditsFeed` reads `/v1/organizations/cost_report` every 15 min and shows
  left = typed − spend since (all in `Credits.swift`). Not "grant − spend since grant": cost_report is org-wide and
  can't say which grant paid (the Parlay logs show ~$100 spent Oct 11–26 while the Console showed only $9.61 drawn
  from the new grant).
- Typing day: cost buckets are whole UTC days. The first read on the typing day stores that bucket as `baseline`;
  with no read that day, counting starts the next UTC day. Pace = last 7 whole UTC days ÷ 7. Amounts are cents.
- Card after the Fable card, only when a balance is set. Chip "Console" (live) or "Typed in"; red line only when the
  pace runs out before the expiry day, or used up; gray "Expired <day>" after it. Amounts with cents
  (`ConsoleCredits.money`). Help section "API credits" (with the `security add-generic-password` command), README
  "API credits" + sources row, CLAUDE.md exception, `--credits-check [file]`, `--status` lines.
- Checked: `swift build -c release` OK (only the old Notifier hint). `--credits-check <sample>` on a made-up
  10-bucket report: cents → dollars right ($1.2429 from "123.78912"+"0.5"), empty bucket 0, next page read, spent and
  $/day match by hand. `scripts/render-all.sh build/renders-0930` OK; the 4 new fixtures look right (crops in
  `build/renders-credits/`); `long` still 1730 px tall, `samename` 1648 (unchanged).
- Replay: the same 3 FAILs as unchanged `main` (stash run, same numbers): This week shares at 86 steps, 14 gate
  points (need 15), 5-hour growth 0.67×. Replay doesn't touch credits.

Not done / unverified:
- **Never hit the real API** (no key on this Mac; probing the keychain is blocked by auto mode). Unverified: that
  omitting `ending_at` returns today's partial bucket, that his key type is accepted, 403 vs 404 for an individual
  account. First thing once Vinnie adds a key: `ClaudeMeter --credits-check` and `--status`.
- 2026-10-28: Vinnie asked to reuse Parlay Builder's key. Tested from the cloud (Parlay thread): cost_report with
  CONSOLE_API_KEY gave HTTP 401, so it's a normal key and can't read spend. Walked him through making an Admin key
  and adding it to the keychain himself. His Console has no Admin keys page; he made an Organization-scoped personal
  key ("Claude Meter") and added it. `--credits-check` read it, but the API said HTTP 403 "Missing permissions": the
  docs say the Admin API is unavailable for individual accounts and his is "Vinnie's Individual Org". Asked him to
  set up an organization at platform.claude.com/settings/organization, then re-run `--credits-check`.
- 2026-10-28 20:51Z: after he set up the organization, `--credits-check` = ok (spent $15.21 over ~3 days, $8.21/day over
  7 days). Live reads work. Still unverified: whether today's partial UTC bucket is included. Next: he types his
  balance (Console header, $107.79 at 20:13Z) via gear › API credits…, then check `--status`.
- v0.9.31: `--credits-check` now also prints Anthropic's refusal (`HTTP 403: <message>`, via
  `ConsoleCredits.lastRefusal`, cleared on each response).
- Vinnie's Console may be an individual account: then the Admin API (cost report) won't work until he sets up an
  organization (free, Console › Settings › Organization). Typed-in mode works regardless.
- The dialog was not click-tested (no-windows rule). Whether a `security`-made item prompts when the app reads it is
  likely-no, not proven.

Previous status (v0.9.29) follows.

## Status (v0.9.29)

v0.9.29 (build 42): **same-named rows say when each session started.** Vinnie saw "Pocket Fishing" under Burning now
and again under Going cold and asked how one session could be both. They were two threads in one folder. The old tags
("Last ran just now" on the burning one, "· 42m" on the cold one) didn't read as "different sessions".
- `Meter.tagSharedNames`: a shared name now tags each row "started <Fmt.when>" (the session's first logged turn) on both
  lists, so a session keeps one tag as it moves from Burning now to Going cold. Fallback to last ran ("18m"/"now") when
  the first turn is within 5 hours of the logs' edge (`coveredFrom`), or when two rows' start tags still match.
- `SessionsSection`: cold rows show the tag in words after the name ("· started 12:21 PM", fallback "· last ran 27m
  ago", `tagInline`) instead of a bare "· 42m". Burning rows unchanged in layout (tag under the name, gray).
- `samename` fixture: cold rows carry start tags plus one fallback. README, Help (Burning now) and CLAUDE.md updated.
- v0.9.28 (517aebf) was committed but not pushed or installed when this started; it went out with this push and install.
- Checked (2026-10-26 ~20:50Z): `swift build -c release` OK, no warnings in the changed files (only the old
  `Notifier.swift:175` async hint). `scripts/render-all.sh build/renders-0929` OK; `popover-samename-*` 680×1648,
  `popover-long-*` still 680×1730 (340 pt). Live render: burning "Pocket Fishing / Started 8:26 PM", cold
  "Pocket Fishing · started 7:56 PM".
- **Replay FAILs, the same 4 lines on unchanged `main`** (stash run): "This week" shares over the weekly card at 28
  steps (all Oct 26, 32% vs 29% at cap $213 up to 37% vs 33% at cap $265), 5 window openings (need 6), 13 gate points
  (need 15), weekly growth 1.45×. Not this change. The shares/growth pair is new since v0.9.28 and looks like the
  v0.9.27 cold-start pattern (a low weekly cap learned on Oct 26 after the signed-out gap); worth a look on its own.

Previous status (v0.9.28) follows.


v0.9.28 (build 41): **while Claude Code is signed out, a card with nothing recent behind it says so instead of a guess.**
Vinnie saw "~0% · Idle. Next message opens a window." on the 5-hour card while the CLI had been signed out since about
Oct 24 (last probe reading Oct 23 21:43Z), and took the meter for broken. He signed in on Oct 26 17:28Z; the probe
answered again at 17:32:30Z.
- `Probe.isSignedOut` (the signed-out reason only; not-found and couldn't-start keep their old cards).
- `WindowView.blind`, set in `recompute()` after the cards are built, view only: `pct`, `exact`, alerts, calibration and
  the replay see nothing new. 5-hour: blind when idle, `stale`, or last measured more than `staleAfter` (10 min) ago.
  Weekly: blind when not exact and last measured more than a day ago. A Dashboard-fed reading inside those limits
  still shows as before.
- `WindowCard`: a blind card shows "—", an empty track, "Signed out, so no reading." / "Sign in to Claude Code to see
  this." on two lines (one was too long for the card), no chip, chart, projection or budget, and the popover drops the
  "Worth …" line under a blind weekly card (its Other part is the weekly estimate). The orange footer stays.
- A good `/usage` report (`refreshFable`, which runs before the window gate) clears a signed-out `probeError` and
  `probeRetryAt`: the report needs a sign-in too. Without it, signing in while idle left the cards on "Signed out"
  until the next message, since probes only run while a window is open.
- Help's orange-line callout mentions it. New popover fixture `signedout` (also in `render-all.sh`).
- Checked: `swift build -c release` OK; `scripts/render-all.sh build/renders-0928` OK, `popover-signedout-*` look
  right, `long` still 680 px (340 pt).
- **Replay FAILs, identically on unchanged `main`** (back-to-back stash runs, same lines): 12 probe gate points (need
  15), 5-hour growth 0.47×, weekly growth 0.79× (an earlier pair also had only 4 window openings, need 6; the numbers
  move as live readings arrive). Data drift from the signed-out gap (Oct 24–26 has no
  probe readings, only Dashboard-fed ones), not this change. Not fixed here; it should recover as probe readings
  build up again over the next days, or the floors need another look.

Not done / known gaps:
- The menu bar title still shows "~0%" when the 5-hour card is blind (out of this brief; the title has tight width
  rules, see CLAUDE.md notes).
- The replay doesn't exercise the blind rule; `signedout` sets the flag by hand, so the `recompute()` rule and the
  `/usage` clear are checked by reading only. No Tests target exists.
- Install (`scripts/build.sh --install`, background relaunch) waits for Vinnie's OK: a new binary can raise one
  on-screen keychain prompt for the cloud feed.

Previous status (v0.9.27) follows.

v0.9.27 (build 40): **replay PASS again.** `./scripts/replay.sh` had failed 3 real-data checks on `main` c3a0301 and
identically on c48ee1b (before the cloud feed), so not a cloud regression:
- Weekly growth 1.24× and "This week" shares above the weekly card (45 steps, Oct 23): a real cold-start bug. From a
  blank state the first weekly cap came from a 5% reading ($142 from $7 of this Mac's spend; the week's start was spent
  away from this Mac) and the blend only nudges a held cap at low %, so it still read $170 at 10% while the spend implied
  $225. Fix in `Meter.calibrate`: the first weekly cap (none, or an old basis) needs 10%, as the 5-hour's; a held cap
  still learns from 5%. Weekly accuracy went ±0.31 → ±0.06. Only fresh installs (or a reset state.json) ever hit it; the
  live cap carries over weeks. Checked: no transcript turn is in two files in the burst (LogIndex dedupes globally).
  A gate in the replay instead (judge weekly only after a cap learned at 10%+) was tried and still failed: the bad cap
  lingers. Guarded only by today's real data, no synthetic case.
- "Only 7 window openings checked, need 8": data drift. 7 of the 8 days' 16 openings came from cloud/phone use, which
  can't be checked here; the 7 checked had 0 failures. `Replay.minimum.openings` 8 → 6; `skipped > checked` still fails.
- Replay now: 7 openings, 18 gate points, 5-hour ±0.31 growth 0.91×, weekly ±0.06 over 39 checks growth 0.75× (not
  judged: under 5 points of measured growth), 79 synthetic, PASS.

Previous status (v0.9.26, the cloud feed) follows; it's merged as c3a0301.


v0.9.26 (build 39): **one cloud feed shared by Meter, Dashboard and Swarm Watch**, asked for by Vinnie ("Give Claude
Meter that same feed. 'Elsewhere' stops reading about $0 and the weekly total becomes a real number instead of a
floor."). Written on a Linux box with no Swift compiler: **not compiled, not replayed, not rendered**. A Python mirror
of the ledger rules and the replay's cloud expectations was run here (scratch, not committed): they hold. Run the Mac
test plan below before merging or installing.

What was built:
- `CloudFeed.swift` (new). `CloudSessions.read()`: Swarm Watch's reader (`Bridge.fetch` + `Credentials`, as Claude
  Dashboard's `CloudReader` copied it): GET `https://api.anthropic.com/v1/sessions`, three listings (default,
  `tags=hearth-thread`, `tags=rc-child`, `limit=50`), `anthropic-version: 2023-06-01`, `anthropic-beta:
  ccr-byoc-2025-07-29`, `x-organization-uuid` from `.claude.json` (`$CLAUDE_CONFIG_DIR`, `~`, `~/.claude`). Token from
  `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w` on a utility thread (it can wait on a macOS
  prompt), in memory only, re-read once on 401/403 (at most every 15 s), dropped when the setting goes off. Signed out
  or 429 stops a read; another failure keeps whatever listings answered. `CloudFeed` (main actor) polls from the
  meter's 10 s tick: 20 s after launch, then every `cloudPollSeconds` (300), 900 after a 429.
- `cloud.json` (`Paths.cloud`, 0600, pretty JSON): `sessions` {id, title, cost_usd, created_at, updated_at, model, cwd,
  seen_at, local}, kept 60 days after last listed (so one that drops off the 50-row lists and comes back isn't booked
  whole again); `ledger` [{at, from, seen, session, title, delta, model}] kept 14 days; `rcChild` (same shape);
  `state`, `readAt`, `triedAt`. Dates are ISO 8601 like every other file the app writes (the brief said epoch seconds;
  the app's convention won).
- Booking (`CloudStore.take`): first sighting books the whole `cost_usd` dated `updated_at` (clamped to the read) with
  `from` = `created_at`; later reads book `cost - last` at `updated_at` when it moved, else at the read, with `from` =
  the previous read; a fall re-bases silently; an entry is unique by (session, seen). **Spans:** every count of the
  ledger over a range (week, day, window) takes each entry's share of its [from, at] span inside the range, evenly. So
  a session already running before the week began counts only its share since, and a first sighting at launch doesn't
  land whole on today or on the 5-hour window. Remote Control work run on this Mac (tag `rc-child` or
  `remote-control-sdk`, an id in `~/.claude/sessions/*.json` `bridgeSessionId`, or a `session_context.cwd` that is a
  folder under your home here) goes to `rcChild`, shown nowhere.
- Numbers (`Meter`): `cloudSpend` (the ledger, sorted; empty with the setting off) and `spend(from:to:)` = this Mac's
  turns + `cloudCost`. Used in `impliedCap` (calibration, both windows), the estimate between readings (`fiveHour`,
  `weekly`, both their lapsed branches) and the pace (`project`). **That is item 4 of the brief, done as a dollar
  series beside the turns, not as pseudo-turns:** a pseudo-turn would also have reached the probe gate (`windowOpen` /
  `openWindow` treat any turn as a message here, so a cloud booking could let a probe open a window), Burning now,
  the runaway alert and its notification, Today, the Fable split and History. None of those use `spend`.
  No basis bump: `blend` moves the caps toward the cloud-inclusive value at most 1.5× per reading.
- `WeekValue.cloud` (exact, nil with the setting off or before the first answered read), `ValueDay.cloud`, and
  `elsewhere` redefined as **Other** = the weekly points left after this Mac's and the cloud's shares (≥ 2 points),
  in dollars at the cap (= max(0, estimate − cloud)). Total = mac + cloud + Other; "~" only with Other.
- "This week" (`fillWeekShares`): cloud rows "Cloud: <title>" grouped by title, pct = cloud $ / capWeek × 100
  (`Share.cloud`, gray bar); the leftover row reads "Other (chat, phone, other computers)"; the summary reads
  "41% this Mac · 12% cloud" when there is cloud.
- Views: Value this week's bar and legend have a third gray (mac 0.72, cloud 0.42, Other 0.2; the legend falls back
  to short names if four entries don't fit), the day columns stack the cloud on this Mac. `WeekValueLine` unchanged.
  `HistoryFootnote` and Help (Weekly, Today / This week, Value this week, settings, sources) updated.
- Settings: right-click → "Cloud sessions" (symbol `cloud`, UserDefaults `cloudSessions`, default on).
  `--status` gains "cloud sessions: <state>, last read Nm ago, last tried …" and "cloud this week: $X across N
  titles since …". `--cloud-check` does one read and prints the state, row counts, the week's cloud $ (as a first
  read would book it) and the top 5 titles, without touching `cloud.json` (exit 0 when the list answered).
- Fixtures: warn, critical, long (popover) and fits (History) carry a cloud part with a smaller Other; `week` has a
  "Cloud: …" share; new History fixture **`cloudonly`** (cloud > 0, no Other, so no "~"; named lowercase like the
  others, the brief said `cloudOnly`), added to `render-all.sh`.
- Replay section 6: `cloudChecks` (18 new checks): booking (first sighting, a JSON round trip then the same listing
  books nothing, a rise at its update, a rise without one, a fall, a rise after it, `rcChild`, a row without a cost,
  the 14-day prune, `isLocal`), and the meter (the week's cloud part with a span across the week's start, the days
  adding up, the "Cloud: …" shares at the cap, Other as the remainder and the total, no Other → no "~", the estimate
  moving with cloud spend after a reading, the weekly cap learned from mac + cloud, the setting off). The replay's
  own meter never reads `cloud.json` (`CloudFeed` is lazy and only `start()`/`loadOnce()`/the toggle make it).
- Version 0.9.26, build 39 (`Resources/Info.plist`). CLAUDE.md has the dated exception.

Not done, follow-ups:
- `rcChild` is booked and kept 14 days but used nowhere. A later reconciliation could compare it with the transcripts'
  price for the same sessions (are `cost_usd` and `Pricing.swift` the same prices?). Today rc-child rows carry no
  `cost_usd` (Claude Dashboard, 2026-10-16), so it is likely empty.
- History's 5-hour windows, the week chart and Plan fit still estimate from this Mac's logs alone.
- No UI for the feed's state beyond `--status` (no new window or menu bar text, per the rules). A signed-out feed is
  quiet: the Cloud part just stops growing.

### Mac test plan (cloud feed, v0.9.26)

All in the background, nothing shown on Vinnie's screen. From `~/Code/Claude Meter`, on branch `feat/cloud-feed`:
1. `swift build -c release 2>&1 | tail -20`: no errors. Likeliest spots if it fails: `CloudFeed.swift` (the
   `offMain` generic continuation, the local `Box` class in `check()`, `nonisolated(unsafe)` statics), `Replay.swift`
   `cloudChecks` (nested functions passed as closures), `WeekValueSection.legend` (`ViewThatFits`).
2. `./scripts/replay.sh`: no `FAIL: synthetic:` lines; the section 6 line ends "…, cloud sessions)" and its count
   is 18 higher than on `main`. Data FAILs from before may still show; compare with the same run on `main` (only new
   FAILs count). Replay doesn't read `cloud.json`, so the data checks must be unchanged.
3. `"$(swift build -c release --show-bin-path)/ClaudeMeter" --cloud-check; echo "exit $?"`: the first run may show
   one macOS keychain prompt (allow it); expect `cloud sessions: ok`, a "listed: N sessions (…)" line, and "cloud this
   week since <weekly start>: $X across N titles", exit 0. Note the numbers here. "signed_out" means no token was read
   (or a 401/403 twice): check `security find-generic-password -s "Claude Code-credentials"` finds the item (it prints
   its attributes, no secret). If Vinnie's Claude Code uses `CLAUDE_CONFIG_DIR`, the keychain service may carry a
   suffix; Swarm Watch's plain name is what is used here.
4. `scripts/render-all.sh build/renders-cloud`: no failures. Look at `history-fits-*`, `history-cloudonly-*` (three
   grays on the bar, the legend in one line, stacked day columns, no "~" in cloudonly), `history-thismac-*` (unchanged:
   no cloud), `popover-week-*` (a "Cloud: …" row with a gray bar, "Other (…)" row, summary "… this Mac · 5% cloud"),
   `popover-warn-*`/`popover-long-*` (the weekly card's "Worth …" line, still with "~"; `long` must still be 340 pt),
   and `help-*` (new sentences). Fixture renders use the dev binary's plan (Max 5x).
5. `"$(swift build -c release --show-bin-path)/ClaudeMeter" --window-check; echo "exit $?"`: exit 0, as before.
6. After Vinnie's go-ahead to install (`scripts/build.sh --install`, background relaunch): within a minute,
   `~/Applications/ClaudeMeter.app/Contents/MacOS/ClaudeMeter --status` shows "cloud sessions: ok, last read 0m ago"
   (the installed app is another binary, so the keychain may prompt once more, on screen: say so to Vinnie first) and a
   "cloud this week" figure close to step 3's. `ls -l ~/Library/Application\ Support/ClaudeMeter/cloud.json` shows
   `-rw-------`; `grep -c -i 'bearer\|accessToken\|sk-ant' ~/Library/Application\ Support/ClaudeMeter/cloud.json`
   prints 0. A day later, `--status` "calibrated caps" week should sit higher than before on cloud-heavy weeks.

Deploy: only with Vinnie's typed go-ahead (merge `feat/cloud-feed` into `main`, then `scripts/build.sh --install`).

v0.9.25 (build 38), from 2026-10-23 (`fix/audit-2026-10-23`, merged to `main` as c48ee1b):
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
- Cost of v0.9.15: the usage report now launches every 5 minutes whenever no window is known open (most of an idle night), about 3 seconds of CPU each.
- Use off this Mac (cloud sessions, claude.ai) shrinks the calibrated cap, because each reading divides local spend by a % that includes the other use. On Oct 10 it fell from about $198 to $76. The live % stays exact (a reading every minute). Burning now's %/hr and the estimate between readings run high on cloud days.
- Tried and rejected: skipping calibrations that imply a much smaller cap (to ignore cloud use). Estimates and the pace then grew only 0.5x as fast as the readings on cloud days, so "capped at" and the cap warning would come late. Replay's growth check fails.
- Tried and rejected: a 5-minute hold on the probe gate after a reset. It fails replay by blocking probes after real window openings.
- The 5-hour % weights turns by API list price (`Pricing.swift`). A new model id falls back to the newest price in its family. Update the table when models change.
- Desktop thread titles come from `~/Library/Application Support/Claude/claude-code-sessions/*/local_*.json`, an undocumented format. If it changes, rows quietly fall back to folder names.
- The app's Remote Control placeholder title is matched by prefix ("Remote Control session"). If the app changes that wording, the placeholder shows again; check one record's `title` first.
- Keep the folder at `~/Code/Claude Meter`. Scheduled checks and Claude Code history depend on that path.
