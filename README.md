# Claude Meter

Menu bar meter for Claude plan limits: the 5-hour window and the weekly cap, with the time
to reset, a pace projection, and where today's usage went by project.

```
◔ 23% · 18m          ← 5-hour window used · time to reset. ~ means estimated.
```

The ring fills to the exact 5-hour %.

## What the dropdown shows

- **5-hour window**: %, reset time, a chart of the window so far with a dashed pace line to
  the reset, and where that pace lands (or when it hits the cap).
- **Weekly**: the same without the chart, plus per-model weekly buckets when a reading has them.
  The forecast leads with your average pace (from exact readings only: this week's average
  until the history log covers 3+ days, then a 7-day average) and gives today's pace second,
  plus a **budget**: what's left per day to last to the reset, against what you average.
  A log-based average isn't used because the logs price each model differently, and a model
  change inside the span (Opus 5 to 5.5, Sep 22) skews it.
- **Accuracy**: an exact reading is compared with what the meter would have shown for that
  moment knowing only a reading 15 to 60 minutes older (the estimate you'd see if readings
  stalled), at most one check per window per 15 minutes (`checks` in `state.json`); the dropdown
  shows the typical error. Readings come about once a minute while you work, so comparing with the
  previous one would measure almost nothing. Whole percents make ±0.5 the floor.
- **Burning now**: each session that spent in the last 15 minutes, by title, with $/hr and
  points of the 5-hour window per hour. Titles come from the transcripts' `custom-title` /
  `agent-name` lines.
- **Going cold**: sessions idle 15+ minutes whose 1-hour prompt cache expires soon, and what
  their next message would cost on top of a warm one once it has (the whole context is
  re-written at 2x input instead of read at the cache price).
- **Today / This week**: spend by project today, or each project's share of the weekly
  limit, plus what the logs can't account for (chat, other devices).

**Runaway alert.** A single session that uses 20%+ of the 5-hour window within 30 minutes
gets a ⚠ in Burning now and one notification per window, to catch loops and large workflows
while you're away.

**Cap warning.** When the 5-hour pace hits the cap at least 10 minutes before the reset, the
menu bar switches to `31% · cap 10:49 PM` in orange, and one notification fires when the cap
is 30 minutes out. It clears once the pace lands under 95% at the reset.

**History** (button, or right-click → History…): every 5-hour window of the last 7 days at its
peak, this week's climb against an even pace, and plan fit: how the same usage would have
gone on Pro, Max 5x and Max 20x. Exact readings are logged to `history.jsonl` from 0.6 on;
windows before that are estimated from the logs.

**Help** (gear menu, or right-click → Help…): a window that explains everything above in plain
words, section by section.

**Shortcut** ⌃⌥⌘U opens the dropdown from anywhere (Carbon hot key, no accessibility
permission needed). Right-click the menu bar item for Sync, History, Help and settings: open at
login, weekly % in the title, notifications, the shortcut.

## Where the numbers come from

Anthropic's limits are exact only on Anthropic's side. The meter takes an **exact reading**
about once a minute while you work and fills the time between from the **local logs**:

| Source | What | When |
|---|---|---|
| `~/.claude/projects/**/*.jsonl` | every Claude Code turn on this Mac: model, tokens, project | continuously (tailed every 10s); `CLAUDE_CONFIG_DIR` is honoured, read from your login shell since apps don't inherit it, and symlinked project folders are followed |
| probe | Claude Code's `rate_limit_event` (exact) | at most once a minute, only if something was logged since the last reading and a window is already open; **Sync** on demand |
| statusline tap | Claude Code's own `rate_limits` (exact) | whenever a **terminal** `claude` session redraws its statusline |
| `tap.json` drop-in | any exact reading, from anywhere | when written |

A turn is logged once per content block, and the first copy can be written mid-stream with a
partial output count; the meter keeps the largest copy of each. Each turn is weighted by API
list price (`Pricing.swift`); a model the table doesn't know is priced as the newest of its
family. An exact reading fixes the
$-equivalent that equals 100% of each window (the *cap*); between readings the % moves by
logged spend ÷ cap. Checked 2026-09-24: estimate 22% vs exact 23% after 12 heavy minutes.

What the estimate cannot see: claude.ai chat, the phone, other machines. Those are corrected
at the next exact reading, and they push the cap estimate low, so the meter errs high.

**Early resets.** Anthropic sometimes resets a window's usage before its reset time (Oct 7: the
weekly went from 87% to 0 mid-week, same Wednesday reset; the 5-hour window moved to a new one
that began before the old one was due). A probe reporting a drop of 3+ points for the same window,
or a 5-hour window that began before the held one was due, is taken as that: the window counts
from the last time the old one was measured (`restartedAt`), its 80%/95% alerts can go out again,
"This week" and the weekly pace count from there, and History's week drops to 0 and cuts the old
window short. It calibrates from there too, unless the reset was noticed more than 30 minutes
after the last measurement: it still counts from that measurement (the spend since is real, and at
worst a little of the old window's lands in the new one), but nothing says when in between it
happened, so it teaches no cap. A window that ran past 80% and is cut short gets the same "back to a
full window" alert as at a normal reset. A smaller drop from
a probe, and any lower or unchanged % from the statusline, is an old number re-sent; once a window
has been reset early the statusline is ignored for it, since it may redraw numbers from before.

**A window nothing measures.** If readings keep arriving but one window isn't in them for ten
minutes (a probe left the weekly out for an hour after the Oct 7 reset), its % is the last
measurement plus this Mac's spend since, which says nothing if Anthropic reset it in between: on
Oct 7 the card read 97% for a week at about 10%, and a false "weekly at 95%" went out. Such a window
is *stale*: the card still estimates, but no 80%/95%/cap alert is raised from it until it is measured
again, when it is raised as usual.

## Build

```bash
./scripts/build.sh --install     # → ~/Applications/ClaudeMeter.app, launched
```

The log index is cached at `~/Library/Caches/ClaudeMeter/index.plist` (a warm launch reads
it in about a second instead of scanning every transcript; delete it to force a full scan).

`ClaudeMeter --render out.png [--dark] [--history | --help-page]` draws the popover (or History, or
Help, whole rather than scrolled) offscreen and
prints the menu bar title, for checking the UI without screen-recording access. `--fixture <name>`
draws a made-up state instead of the live one (`Fixtures.swift`), and `scripts/render-all.sh <dir>`
renders every state, light and dark, plus History, Help and the menu bar ring. A render that couldn't be
drawn or written exits 1, and a mistyped command exits 2.

`~/Applications/ClaudeMeter.app/Contents/MacOS/ClaudeMeter --status` prints how the app is
set up (open at login, notification permission, CLI found) and what it last knew (last exact
reading, calibrated caps, accuracy).

`swift scripts/make-icon.swift [previewDir]` redraws `Resources/AppIcon.icns` (and, given a folder,
writes a 1024px PNG and a contact sheet of every size there).

## Replay test

```bash
./scripts/replay.sh
```

Builds the working tree and steps the real meter code through this Mac's history log and
transcripts with a moving clock, from a blank state (calibration learned along the way). Reads,
never writes (the store is read-only, so not even a harness can add to the history log), apart
from starting your login shell once to find `CLAUDE_CONFIG_DIR` when it isn't set; exits non-zero
on a failure. It checks:

1. **Window openings**: after each reset, the estimate of the next window's reset, made from what
   was known at the reset, matches the real one within a minute. A transcript line is written when
   the reply arrives, so a first message logged within a minute of a 10-minute mark may have opened
   the slot before; there either slot passes (the probe a minute later reads the real reset).
2. **Probe gate**: between a reset and the next message a probe would not run (it would open a
   window); right after that message it would.
3. **Alerts**: none goes out twice for the same window unless Anthropic reset it early in between,
   and every threshold, cap warning and runaway the dropdown called for was sent, and every
   threshold alert has a reading of that window behind it (alerts go to a recorder, not macOS).
4. **Accuracy**: estimates 15 to 60 minutes after a reading, typically within ±1.5 points
   (5-hour) and ±1.0 (weekly), and growing as much as the readings say (1.00 ± 0.12, which
   catches a wrong cap that the typical error is too coarse to see).
5. **Consistency**: the early resets the meter recorded are the ones the readings show; the
   "This week" shares never add up to more than the weekly card; History's windows don't overlap,
   don't hold another window's readings, there is one window for each group of readings (an early
   reset's is its own, not stuck on the one it cut short), and an uncapped one doesn't peak above
   its readings.

It also fails when it ran too little to mean anything (fewer than 8 openings, 15 gate points or
30 accuracy checks). The weekly floor is lower the less of the week the logs cover: they reach back
8 days, so just after a weekly reset there is little or nothing to check, and that isn't a failure.
It's the full 30 once the week's readings span half a week, scaled down below that, and with under
a day's worth it asks for none (and judges no fewer than 8 checks).

Each reading is replayed with only the windows it measured: the history log also keeps windows
carried over from earlier readings (past the 5-hour cap the probe stopped reporting the weekly), and
those aren't new measurements. Checks 1 and 2 judge from the state at the reset, so readings the pre-0.8 probe took seconds
after a reset (which opened those windows itself) don't count against today's code. Openings that
an early reset moved, or that were opened away from this Mac, are skipped. Each check was
confirmed to fail when the fix it guards is removed.

What it doesn't cover: `sync()` (the once-a-minute cadence, the retry backoff, stamping at launch
and the rule that a rejected answer isn't asked for again while idle), the statusline tap, and
early resets beyond the ones in the data (it can only replay what the history log holds, and the
log keeps five weeks).

## Uninstall

```bash
./scripts/uninstall.sh
```

Quits the app, removes its login item, the app, its data and cache, its preferences, and the
statusline entry in `~/.claude/settings.json` (only if it is exactly the tap; a statusline that
runs something else too is left for you to edit).

## Probe

One headless Claude Code turn: `claude -p ok --model haiku`, a one-line system prompt, no
tools, no MCP servers, no saved session, none of your settings or hooks
(`--setting-sources ""`, `disableAllHooks`), run in an empty folder. Claude Code reports the plan
limits alongside the reply (`rate_limit_event` → `unifiedWindows`, utilization as a fraction).
About $0.001 of usage per run, so at most ~$0.06/hr while you work (about 0.03 points of the
5-hour window per hour) and nothing while idle.

- **It never opens a window.** A probe is a request, and a request opens a 5-hour window if
  none is open, which would move your reset. So it only runs while the last reading's window is
  still open, or once you've sent something since it reset; a forced Sync with no window open
  says so instead.
- It finds the native installer, Homebrew, npm (with node on its PATH), Volta, Bun and nvm.

- It strips `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY` and `ANTHROPIC_AUTH_TOKEN` first. The
  desktop app sets the first for everything it launches, and any of them would move the call
  off the subscription onto API billing.
- It needs the Claude Code CLI signed in to the subscription (`claude` → `/login` → Claude
  account). The meter never reads the token; Claude Code refreshes it itself. If the CLI is
  signed out (or missing), the footer says so and the probe retries every 5 minutes (it fails at
  once and spends nothing); any other failure (offline, a slow machine) retries after a minute,
  doubling up to 30 minutes.
- Not in the last two minutes before a window's reset: a probe launched then could reach the API
  after it and open the next window.
- Each reading is stamped when its probe starts (when it answers, if it took over 90 seconds, say
  the Mac slept), and a probe is called for
  only by activity logged after the last one started, so a turn logged while it ran is not lost
  and an answer that was turned away is not asked for again while you're idle.

## Statusline tap

`claude-meter-tap` (inside the app bundle) is a Claude Code statusline command. It saves the
exact `rate_limits` block (only when it changes). The statusline redraws without new API calls
and stamps the time it drew, so from it only a higher % than the meter already has counts as a
new reading, and a window it leaves out (it drops one the moment it resets) is kept as the reset
to walk on from. It prints `Opus 5.5 · 5h 23% · 7d 28% · ctx 21%`, each percentage (the limits
and the context) in yellow from 70% and red from 90%, plain when `NO_COLOR` is set and not empty
(no-color.org). Registered in
`~/.claude/settings.json`:

```json
"statusLine": { "type": "command", "command": "~/Applications/ClaudeMeter.app/Contents/MacOS/claude-meter-tap" }
```

## Dropping in a reading

Write `~/Library/Application Support/ClaudeMeter/tap.json` (epoch seconds):

```json
{ "at": 1790289060, "source": "app",
  "rate_limits": { "five_hour": { "used_percentage": 23, "resets_at": 1790290200 },
                   "seven_day": { "used_percentage": 28, "resets_at": 1790794800 } } }
```

State (last exact reading, calibration, notifications sent) is in `state.json` next to it. A
state file this version can't read is kept as `state.unreadable-<time>.json`, never overwritten.
`history.jsonl` keeps five weeks, a line per reading (about one a minute while you work, a few MB
at the most). A reading dated in the future is ignored, and `at` may be in seconds or milliseconds.

## Notifications

At 80% and 95% of each window, once per window, and when a 5-hour window that passed 80%
resets. **Send test notification** (gear or right-click menu) checks they get through; if macOS
is blocking them it opens the Notifications settings pane.
