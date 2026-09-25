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
- **Accuracy**: every exact reading is compared with what the meter was estimating at that
  moment (`checks` in `state.json`); the dropdown shows the typical error. Exact readings from
  the desktop app are whole percents, so ±0.5 is the floor.
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

**Shortcut** ⌃⌥⌘U opens the dropdown from anywhere (Carbon hot key, no accessibility
permission needed). Right-click the menu bar item for Sync, History and settings: open at
login, weekly % in the title, notifications, the shortcut.

## Where the numbers come from

Anthropic's limits are exact only on Anthropic's side. The meter takes an **exact reading**
every 15 minutes while you work and fills the time between from the **local logs**:

| Source | What | When |
|---|---|---|
| `~/.claude/projects/**/*.jsonl` | every Claude Code turn on this Mac: model, tokens, project | continuously (tailed every 10s) |
| probe | Claude Code's `rate_limit_event` (exact) | every 15 min while active (5 min past 75% or under a cap warning, 1 min after a reset), only if something was logged since the last reading; **Sync** on demand |
| statusline tap | Claude Code's own `rate_limits` (exact) | whenever a **terminal** `claude` session redraws its statusline |
| `tap.json` drop-in | any exact reading, from anywhere | when written |

Each turn is weighted by API list price (`Pricing.swift`). An exact reading fixes the
$-equivalent that equals 100% of each window (the *cap*); between readings the % moves by
logged spend ÷ cap. Checked 2026-09-24: estimate 22% vs exact 23% after 12 heavy minutes.

What the estimate cannot see: claude.ai chat, the phone, other machines. Those are corrected
at the next exact reading, and they push the cap estimate low, so the meter errs high.

## Build

```bash
./scripts/build.sh --install     # → ~/Applications/ClaudeMeter.app, launched
```

The log index is cached at `~/Library/Caches/ClaudeMeter/index.plist` (a warm launch reads
it in about a second instead of scanning every transcript; delete it to force a full scan).

`ClaudeMeter --render out.png [--dark]` draws the popover offscreen and prints the menu bar
title, for checking the UI without screen-recording access.

`~/Applications/ClaudeMeter.app/Contents/MacOS/ClaudeMeter --status` prints how the app is
set up (open at login, notification permission, CLI found) and what it last knew (last exact
reading, calibrated caps, accuracy).

`swift scripts/make-icon.swift` redraws `Resources/AppIcon.icns`.

## Uninstall

```bash
./scripts/uninstall.sh
```

Quits the app, removes its login item, the app, its data and cache, its preferences, and the
statusline entry in `~/.claude/settings.json` (only if it points at the tap).

## Probe

One headless Claude Code turn: `claude -p ok --model haiku`, a one-line system prompt, no
tools, no MCP servers, no saved session, run in an empty folder. Claude Code reports the plan
limits alongside the reply (`rate_limit_event` → `unifiedWindows`, utilization as a fraction).
About $0.002 of usage per run, so at most ~$0.01/hr while you work and nothing while idle.

- It strips `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY` and `ANTHROPIC_AUTH_TOKEN` first. The
  desktop app sets the first for everything it launches, and any of them would move the call
  off the subscription onto API billing.
- It needs the Claude Code CLI signed in to the subscription (`claude` → `/login` → Claude
  account). The meter never reads the token; Claude Code refreshes it itself. If the CLI is
  signed out, the footer says so and the probe retries every 30 minutes.

## Statusline tap

`claude-meter-tap` (inside the app bundle) is a Claude Code statusline command. It saves the
exact `rate_limits` block and prints `Opus 5.5 · 5h 23% · 7d 28% · ctx 21%`. Registered in
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

State (last exact reading, calibration, notifications sent) is in `state.json` next to it.

## Notifications

At 80% and 95% of each window, once per window, and when a 5-hour window that passed 80%
resets. **Send test notification** (gear or right-click menu) checks they get through; if macOS
is blocking them it opens the Notifications settings pane.
