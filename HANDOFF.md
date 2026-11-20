# Claude Meter: handoff

Updated 2026-11-19 (evening, Eastern) by Claude: version 1.3 (build 103) = "Personal burn" below, shipped on Vinnie's
"commit, tag v1.3, push, install and restart Claude Meter" (Nov 19, 7:58 PM Eastern): committed, tagged v1.3, pushed
and installed. The next version is 1.4 (build 104).

Before that, 2026-11-11: version 1.2 (build 102) = the shared cap warning below, shipped on Vinnie's "commit push
and ship please" (Nov 11, 2:52 PM Eastern): committed, tagged v1.2, pushed and installed.

## Personal burn (2026-11-19; Vinnie: "doesnt look like its tracking my specific burn anymore")

His dropdown on Thu Nov 19 at 7:15 PM Eastern (Ultra, week-only, week reset Wed Nov 18 2:00 PM): weekly 6%, "Worth
$60.48 so far", Today $3.10, "This Mac: <1% of the week ($2.46)", day bars nearly empty, no Burning now rows, after
a day of Fable work in cloud project threads.

What the diagnosis found (figures from that evening):

- This Mac's side was right. Four transcripts that day, $3.10 at 7:15 PM (Fable 5.2 $2.46, Sonnet 5.5 $0.64), all in
  the index; no new path layout, no `CLAUDE_CONFIG_DIR`, cache version fine. His work simply wasn't here.
- By design Today, the 7 day bars and the Fable line counted this Mac alone; cloud sessions only showed under This
  week. That evening the ledger held $51.84 of cloud spend for the day ($62.50 for the week; Fable $16.81 and
  $27.47). So Today would have read about $55, and the Fable line "~2% of the week ($29.93)", had they counted it.
  This was most of what he saw.
- The sessions list is ordered newest-created first and the feed read 50 rows of each listing, once, with no
  paging. Paged to the end: default 19, `hearth-thread` 138, `rc-child` 166. Of the 15 threads used since the week
  began, 1 sat past row 50: "Parlay Builder next steps" (row 118, made Oct 11), known at $336.28 since Oct 26, now
  $425.02: $88.74 never booked. Older misses of the same kind: "Forgelight Studio site" +$47.78, three Pocket
  Fishing threads +$10.69, and 20 threads from Oct 7-10 never seen at all ($267.96 whole, one of them "Console
  credits runs" $77.40, last used Nov 18).
- Every project thread has a parent the three listings never return: the project coordinator (the session behind
  each project's own chat), tag `hearth-overview`, with a `cost_usd` of its own. 280 of them, $671.82 whole, none
  ever booked; 9 used that week, $17.72. Other tags tried (`hearth`, `aibo`, `hearth-joined`, `hearth-rc-child`)
  add nothing new. `rc-child` rows still carry no cost (37 of 166 carry token counts only).
- Not explained: "Share by app" said Duet 24% that week. No listing shows Duet sessions, so that part can only sit
  in Other.

What changed (1.3):

1. `CloudSessions.read` pages every listing to its end: `limit=100` (the list refuses more), `after_id=<last_id>`
   while `has_more`, 30 pages at most a listing (`maxPages`; past that the oldest go unread, as before, and
   `--cloud-check` says "cut short"). A cursor that doesn't move stops the listing. A sign-out or a 429 on any page
   stops the read with nothing booked (the next read, 5 minutes on, starts over; a read is now about 8 GETs, not
   3, so one 429 costs more than it did); any other failure ends that listing and keeps the pages already answered.
   The read itself (`read(bridged:home:fetch:)`) takes its GET as a closure so the replay can feed it a made-up
   list; `CloudSessions.wait` runs one read to its end for `--cloud-check` and the replay.
2. A fourth listing, `tags=hearth-overview`: the project coordinators. They show as "Cloud: Project coordinator
   ("Utilities")" rows; all of a project's coordinators share that title, so they add up in one row.
3. `CloudStore.take` is unchanged, on purpose. A session known at an old cost that is listed again books only its
   rise, at its `updated_at`, spread evenly from its last sighting (so Parlay Builder's $88.74 over Oct 26 to
   Nov 19 puts $4.16 into this week). A first sighting is booked whole over its own life, which for a coordinator
   is hours, so its spend lands on the right days.
4. Today counts the cloud sessions (`fillToday`): `todayCost` is this Mac plus cloud, `todayCloud` the cloud part,
   "Cloud: title" rows among the projects (`Row.cloud`, the bar This week gives them), the models line by each
   session's model, and the 7 day bars each day's cloud spend (`DayBar.cloud`). The header reads "$55.94 · $3.10
   this Mac · $52.84 cloud", "$78.97 · $13 Mac + $66 cloud" or "$6.1k · this Mac + cloud", the longest that fits
   (`ViewThatFits`); tokens and cache, this Mac's only, moved to its tooltip. With no cloud spend today the header
   is the old one. The menu bar's "$0.42 today" title (shown only while no limit card is known) is `todayCost` too,
   so it now counts the cloud as well.
5. The Fable card's line counts cloud sessions on Fable (`cloudFable`, `CloudSpend.fable`, by the model that last
   served the session when each rise was booked): "This Mac + cloud: ~4% of the week ($42.37)", "Mac + cloud: …"
   beside a 5-hour part, and "This Mac: …" as before while the list isn't read (`FableView.cloud`).
6. `--status` adds "cloud today: …". `--cloud-check` lists each listing's rows and pages and says what the read
   would book on top of `cloud.json` ("against cloud.json: …"), still writing nothing.
7. Fixture `cloudtoday` (in `render-all.sh`); `long` now carries a long cloud row, the widest Today total and the
   longest Fable line. Help, README and CLAUDE.md (exception and a lesson) say the same.

With Cloud sessions off, nothing above changes anything: the ledger is empty, so every number and word is 1.2's.

What the first read after an install will do (worked out with the working tree's `--cloud-check` at about 8:40 PM
Eastern on Nov 19, which writes nothing):

- It books about 104 new entries, $381 in all (what the last 14 days keep of the coordinators, the 20 old threads
  and the rises above). $24.25 of it lands in this week ($20.09 today): the coordinators' $17 or so, Parlay
  Builder's $4.16 share, and whatever the current threads added since the last 1.2 read. The rest lands on earlier
  days, so the 7 day bars for last week grow a little.
- "Worth so far" and the This week rows rise by about that $24 at once (Other, if any is showing, shrinks by as much).
- The weekly % does not jump: every catch-up entry is dated in the past, before the last exact reading, and the
  estimate only adds spend since that reading.
- The weekly cap is not held or excluded from; it is left to learn, and it will go up, not wild. It was learned
  from spend that left the coordinators out, so it is low: $1.2k that evening, where the week's spend with them
  implies about $1.6-1.7k. Each reading moves it about a tenth of the way (the blend's weight is 0.4 x % / 25, and
  1.5x at most a step), so it takes a few hours of use. Until then the This week rows add up to a point or two
  more than the weekly card says (8.5% against 7% that evening) and Other reads nothing. I chose this over
  holding the catch-up out of calibration because the spend is real and dated where it happened; held out, the
  cap would stay low for good. If it reads badly, the catch-up could be held to a cap of its own; say so.
- From then on a read is 8 GETs, not 3, every 5 minutes, growing by one per 100 new sessions.

Checks (Nov 19): `swift build` (the same two warnings as 1.2, none new: checked against a build of the last
commit), `scripts/replay.sh` PASS with 148 synthetic checks (19 new), `scripts/render-all.sh build/renders-1.3` (57
pictures, every dropdown 340 pt wide; looked at `cloudtoday`, `long`, `week` and the live one, light and dark). Each
new check was seen to FAIL with its fix switched off (`build/diag/mutate.py`, four runs: no paging; no coordinators
listing; any failure dropping the read; a sign-out or 429 not stopping it; no ceiling flag; a stuck cursor; a rise
booked at the read instead of spread over the gap; Today, the models, the day bars and the Fable line without the
cloud; the Fable line saying "cloud" with the setting off). The working tree's `--cloud-check` read the real list:
603 sessions in 8 pages (default 19 in 1, hearth-thread 138 in 2, hearth-overview 280 in 3, rc-child 166 in 2).

Not covered by the replay, and not verified:

- The replay's real-data parts judged nothing that day: 0 window openings, 0 gate points, 0 accuracy checks ("the
  week began too recently for the logs to teach its cap"). I did not run the last commit's replay to compare. The PASS rests on
  the synthetic checks.
- The live feed itself (`CloudFeed.finish` saving `cloud.json`) only runs in the installed app. After an install,
  check `--status`: "cloud sessions: ok", "cloud today: …", and "cloud this week" up by about $24 on the first
  read; and that a replay still passes once `cloud.json` holds the catch-up (it adds real spend to last week's days).
- Whether the coordinators' cost counts toward the weekly % the way a thread's does. It is `cost_usd` on the same
  list and the plan's own sessions, so I took it as counted; if the This week rows keep running over the weekly
  card for days, look here first.
- When, inside its gap, a long-unread thread really spent its rise (the list doesn't say). Spread evenly.
- The header's three widths were checked in renders at this Mac's font metrics only.

Suggested, not built (his call): Burning now rows for cloud sessions (a thread that rose in the last two reads,
at $/hr from the ledger; coarse, since the list is read every 5 minutes); the History "By model on this Mac" line
counting the cloud by model too; stacking the cloud on each day bar the way History's columns do.

Before that, 2026-11-10 (01:47Z; the evening of Nov 9, Eastern): version 1.1 (build 101) = the clean-up sweep below
plus the batch Vinnie approved after it (items 10 to 17), shipped on Vinnie's "commit push and ship please": committed,
tagged v1.1, pushed and installed. The next version is 1.2 (build 102).

Before that, 2026-11-04: version 1.0 (build 100) = the review-fix batch below, shipped on Vinnie's "version 1.0 yes, commit
push and ship please": committed, tagged v1.0, pushed and installed. Version naming follows his rule: two numbers, build =
major × 100 + minor. The dated log is in `HANDOFF-HISTORY.md`.

## Shared cap warning (2026-11-11; Vinnie: "send all recommendations and fixes to the appropriate thread and have them all implemented")

Shipped in 1.2. The usage band (`~/.claude/mods/usage-band`, its own repo) works out its orange "cap" warning from
`lastExact` with simpler math, so it could disagree with the menu bar. The meter now writes its own into `state.json`
for the band to show. The band's side is not done here (a different repo and thread).

- `capWarning` in `PersistedState` (`CapWarning`, Limits.swift): `window` ("week" with no 5-hour limit, else
  "fiveHour"), `capAt` (`Snapshot.capWarning`, what `updateWarning` returned: the held warning the title and ring
  use; left out while not warning), `resetsAt` (that window's reset; left out with no such window), `at` (when it
  was worked out). No object at all means a meter before 1.2. Dates as everywhere in the file (ISO 8601 UTC,
  milliseconds). Chosen beyond the brief: `capAt` is left out, not written as null (the file never writes nulls);
  a `capWarning` that won't decode is dropped without setting the file aside, since it is worked out again in seconds.
- `Meter.shareWarning` runs in every `recompute` once the logs are read: the state always holds the newest, and the
  file is written (`CapWarning.needsWrite` against `StateStore.savedWarning`, the copy the file holds) when the
  warning turns on or off, the window or reset changes, the cap time moves 5 minutes, or the copy is 10 minutes old.
  Every other save (each exact reading) carries the newest along. Not in a quiet meter (replay, `--render`,
  `--status`), and `save` refuses a read-only store anyway.
- Cost: with nothing else going on, one whole-file write every 10 minutes (144 a day) where an idle meter wrote none.
  That is the price of `at` telling a reader the meter is alive; the band skips its read while the file is unchanged.
- `--status`: "shared cap warning: week caps Thu 2:49 AM, resets Wed 2:00 PM, worked out 0m ago", "… none (week) …",
  "(old: is Claude Meter running?)" past 15 minutes, or "not written yet". It prints the file's copy, not its own math.
- For a reader: stale when `at` is over 15 minutes old; over when `resetsAt` has passed.
- Docs: README "Reading the meter from another tool"; CLAUDE.md's 2026-11-11 exception. Help mentions neither the
  band nor state.json, so it is unchanged.

Checks (Nov 11): `swift build` (no new warnings), `scripts/replay.sh` PASS with 129 synthetic checks (22 new: the
right window and the menu bar's own value in both modes, on, held at the reset, off, no reading; when the file is
written; a 1.1 file loading; the file's text with the field taken back out equal to the 1.1 text byte for byte, with
`lastExact` and `fable` spelled out; null, odd shapes, a 5-hour plan), and `scripts/render-all.sh build/renders-1.2`
(55 pictures, nothing in the views changed). Seen to FAIL with the fix switched off: no `shareWarning` call, a
`needsWrite` that never writes, the strict decode, the card's raw pace in place of the held warning, the wrong window.
Not covered by the replay: the write itself (a quiet meter never writes), so after an install check that
`state.json` gains `capWarning` and `--status` says "worked out 0m ago". A hidden `--render` run on this Mac's real
logs gave `{"at": "2026-11-11T19:47:08.767Z", "resetsAt": "2026-11-18T19:00:00.000Z", "window": "week"}` (6%, no warning).

## Sweep (2026-11-10; Vinnie: "find everything that's broken, inconsistent, inefficient, or no longer needed. Fix what you're sure about and list the rest")

Every source file, script and doc was read. Fixed, and shipped in 1.1:

1. Pricing: `claude-fable-5-2` and `claude-mythos-5-2` had no row and were priced as Fable 5.1 ($10 / $50, cache reads
   $0.25). They are $8 / $40, cache reads $0.20, with fast mode at 2x. The "fable" and "mythos" family fallbacks follow.
2. Pricing: Sonnet 5.5 cache reads are $0.10 (0.05x input), not $0.20; the "sonnet" family fallback follows. This reverses
   item 7 of the Nov 4 batch. Source for both: the live pricing page, read Nov 10
   (https://platform.claude.com/docs/en/about-claude/pricing). Costs are derived from the cached token counts, so the new
   prices reach old turns at once; the caps re-learn at the next exact reading.
3. Dead code removed: `Snapshot.activeCount` with `Meter.active` and `LogIndex.activeSessions` (computed every scan, shown
   nowhere), `Burn.fable` and `SessionRow.fable` (the bar has been gray since 1.0), `WindowCard.tint` (no caller passed
   one), and `VerdictCallout`'s constant `neutral` with its two dead branches.
4. `MenuBar`: `@discardableResult` and the `--icons` doc comment sat on `isCapTitle`, which had been inserted between
   them and `renderIcons`; they are back on `renderIcons`.
5. VoiceOver: when the title drops the word "cap" to fit ("~99% · Wed 10:49 AM"), the menu bar item's label now adds
   "when the pace reaches the cap".
6. The usage text for a mistyped flag lists `--extra-check` and `--window-check`.
7. Comments that still described the pre-1.0 colours (orange values, a green check, a pink bar, a coloured tick) or the
   5-hour window where the week also applies; a doubled doc comment on `Meter.lastProbe`.
8. Docs: README says the Credits tab still uses the sign-in with Cloud sessions off; "Next steps" below no longer
   lists the two one-off checks that are past.
9. Replay: an early reset from before the replayed span no longer FAILs the run. The meter-side count now only counts a
   restart against a window it already held, as the readings-side count does. (Nov 10: the Oct 30 weekly reset rode in
   on the span's first reading; 900e6fd failed the same way.)

Then, on Vinnie's "go ahead and make all recommended changes please" (Nov 10) for the list that stood under "Not
changed", and "the dots that show what model is running need to be accurate" for item 17:

10. Weekly cap warning with no 5-hour limit: `Notifier.check` raises "Claude weekly cap in ~20m" when the week's cap
    (the last day's pace, `weekly().capAt`) is 30 minutes out or less, once per week, key kind `pace-week`
    (`Notifier.weekPace`); an early weekly reset re-arms it. The replay owes it like the 5-hour "pace".
11. Fable alerts at 80% and 95%, key kind `fable`: only from `FableView.limit` (a real reading whose week is open), once
    per Fable week per threshold, one banner when both are crossed. Not re-armed if Anthropic resets the Fable limit
    early (nothing records that for Fable).
12. Grayscale finished: the "cold in 6m" chip is the gray `Chip` look; Help's Burning now, Going cold and Fable headers
    are gray; "History ›" and the Credits card's "Update ›" are primary text; the footer's probe-failure line is primary
    with its ⚠; footer notices are red only for `loginError`, primary with "exclamationmark.circle" for notifications
    blocked and the shortcut taken, gray with "info.circle" for "Still reading…" and the no-window notice
    (`Meter.isInformation`). Gone with it: `Theme.coldText`, `Theme.text`, `Theme.fable`, the tint of `Chip`,
    `ModuleTitle` and `HelpSection`. `Theme.warnText` stays: Help's orange cap-title sample uses it.
    Decided beyond the brief, same rule: Help has no links, so its two accent pieces went gray instead (the header's
    ring and tile, the lightbulb tip), and its two orange ⚠ callouts with them (one `Callout` look, on `Theme.track`;
    the app's own ⚠ rows lost their orange in 1.0). Say if any should come back.
13. `WindowCard`'s tooltip: "Estimated from what this Mac and your cloud sessions logged since the last exact reading …".
14. API credits pace: the last 7 whole UTC days' spend ÷ the days the report reaches back (earliest bucket to today,
    1 to 7), not always 7. Not checked against a live report (no keychain reads from a dev build): if Anthropic lists
    a bucket for every requested day, empty ones included, this changes nothing; if it leaves empty days out, a key
    that spent only on recent days is averaged over those days.
15. `HistoryFootnote`: "Days spent mostly on a different model than usual (Fable, say) are priced differently…".
16. `build/` cleared of old renders and replay logs; `build/renders-1.1` is this batch's set.
17. A row's model is the session's own loop: `Turn.sidechain` (a line's `isSidechain`, or a transcript under
    `subagents/`; `IndexCache.version` 3, so an older cache is read again), and `recentBySession` keeps the newest
    main-loop turn (`Recent.mainTurn`, looked for past the hour only when helpers alone ran in it). Burning now's
    mascot and tooltip and the header crew use it; spend still counts every turn. Going cold uses it for the model,
    the context re-written and the cold time (the next message goes to the main loop, whose cache counts from its own
    last turn), but a session still waits 15 quiet minutes, helpers included, so it is never in both lists.
    What prompted it was not this bug: on Nov 10 the meter was right (see CLAUDE.md's lesson).

Checks (Nov 10, the whole working tree, and again on the 1.1 tree just before the commit): `swift build` (no new
warnings), `scripts/replay.sh` (PASS, 107 synthetic checks; each new one seen to FAIL with its fix switched off) and
`scripts/render-all.sh build/renders-1.1`.
The replay guards 10, 11, 14 and 17 with synthetic cases only: the real history has no weekly cap warning, Fable
reading or subagent turn in its span. 12, 13 and 15 are looks and words, checked in the renders.

Not changed, for Vinnie to decide (also in the thread "Work on Claude Meter with Fable"):

- `ModelFamily.name` is unused (kept in case the model name goes back inline: see the Mascots decision below).
- Everything still under "Open decisions" below stands.
- Seen on the way, not changed: `BarRow`'s `tint` has no caller passing one; `LogIndex.session(of:)` is only used to
  prune names; `--status` and the Credits card still say "over 7 days" / "this week" for a pace that may now cover fewer.

## Review-fix batch (2026-11-04, from the Fable review; Vinnie: "i want all the fixes implemented")

Review notes: `/private/tmp/claude-501/-Users-vinnie-Code/1e96335e-ac88-4555-acc8-c5dc2d6778d4/scratchpad/claude-meter-review.md`
(a temp path that may be gone; a copy is in the Utilities project's files as `claude-meter-review.md`).
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
   $1.00 are confirmed (Fable 5.1 is $0.25). Superseded Nov 10: Sonnet 5.5 is $0.10 (see the sweep above).
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

1. 1.3 (build 103) is committed, tagged, pushed and installed. Over its first hours, watch the weekly cap settle
   ("Not covered by the replay" above). `state.json` holds `capWarning` since 1.2.
   The usage band still has to read it (its own repo; not started here). What is left for him is under "Not changed" above and "Open
   decisions" below. (The first launch of 1.1 read every transcript again once: the log cache's version changed.)
2. Every Monday 9 AM: the weekly replay check (scheduled task `claude-meter-weekly-replay`) reports PASS or FAIL. Not
   re-checked on Nov 10 that the task still exists. The Oct 15 and Nov 4 one-off checks are past.
   Scheduled tasks run while the Claude app is open, and a missed one runs at the next launch.

## Open decisions (Vinnie's)

- Value this week (v0.9.23): option A is built; option B (the receipt) only means rewriting `WeekValueSection`'s body.
  Day columns are 8 (a 3 PM reset touches 8 dates), not the brief's 7; the alternative is 7 24-hour slices labelled by
  the weekday each starts on. Elsewhere was usually $0 because the weekly cap absorbed cloud use; v0.9.26 counts the
  cloud sessions exactly and in the cap, so "Other" is what's left (claude.ai chat, the phone, other computers) and
  can still be absorbed by the cap the same way.

- Mascots (v0.9.16): commit and push v0.9.16 (his typed words). Read "keep the model name text" in Burning now as keeping the model in the row's tooltip (moved there in v0.9.6 at Vinnie's request), not adding it back inline as the mockup shows; say if it should be inline. Help's section headers still wear the flame and snowflake, and its Burning now sample row has no mascot; left as is. Going cold names get about 70 pt now (was about 110) because of the mascot and family column.

- Fable (v0.9.14): it notifies at 80% and 95% since Nov 10 (item 11 above). Whether to also use the usage report's 5-hour and weekly numbers: it is a free reading that never opens a window, which the probe can't offer with no window open (the "Known limit" below), but it prints whole percents and the probe gives `unifiedWindows` fractions, so it was left out of calibration for now.

- From the 2026-10-11 audit, not done in v0.9.13:
  - Medium 1, Going cold never lists 5-minute-cache sessions: Help says so on purpose ("already cold by then"). Listing them means showing a session in Burning now and Going cold at once, or a shorter idle bar for that tier. Your call.
  - Cache tier from any 1h write (prior #9): kept as decided in v0.9.11.
  - Display and wording: a stale card still reading "exact"; Plan fit verdict wording, "Capped: never" and "Busiest 0%" when uncalibrated, "Exact readings logged since"; a one-day weekly average labelled an average; 99.6 printed "100%"; "~210% by reset" past the 150% pace line; the weekly project row's 0%; the open window bar past the plot edge; the ring dot angle.
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
  to this Mac + Other as the days pass. Since 1.3 every listing is read to its end (`limit=100`, `after_id`), 30 pages
  at most; before, only the 50 newest rows were, and an older thread still in use was never read again. A session
  that does go unread and comes back is re-based from its stored cost (kept 60 days), not booked whole. If paging
  ever breaks (the cursor fields `has_more` / `last_id` renamed), each listing quietly reads its first 100 rows only:
  compare `--cloud-check`'s "listings:" line with the number of threads you know of. `cost_usd` is taken as priced
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
- The 5-hour % weights turns by API list price (`Pricing.swift`). A new model id falls back to the newest price in its family. Update the table when models change, from the live pricing page (https://platform.claude.com/docs/en/about-claude/pricing): Fable 5.2 went a week on Fable 5.1's price, and Sonnet 5.5's cache reads were set wrong on Nov 4.
- Desktop thread titles come from `~/Library/Application Support/Claude/claude-code-sessions/*/local_*.json`, an undocumented format. If it changes, rows quietly fall back to folder names.
- The app's placeholder titles ("Remote Control session (from a project)", "Local session (from a project)") are matched by prefix or suffix (`DesktopTitles.isPlaceholder`). If the app changes that wording, the placeholder shows again; check one record's `title` first.
- Keep the folder at `~/Code/Claude Meter`. Scheduled checks and Claude Code history depend on that path.
