# Claude Meter

Menu bar meter for Claude plan limits: the 5-hour window and the weekly cap, with the time
to reset, a pace projection, and where today's usage went by project.

```
◔ 23% · 18m          ← 5-hour window used · time to reset. ~ means estimated.
```

## What the dropdown shows

- **5-hour window**: %, reset time, a chart of the window so far with a dashed pace line to
  the reset, and where that pace lands (or when it hits the cap).
- **Weekly**: the same without the chart, plus per-model weekly buckets when a reading has them.
- **Accuracy**: every exact reading is compared with what the meter was estimating at that
  moment (`checks` in `state.json`); the dropdown shows the typical error. Exact readings from
  the desktop app are whole percents, so ±0.5 is the floor.
- **Burning now**: each session that spent in the last 15 minutes, by title, with $/hr and
  points of the 5-hour window per hour. Titles come from the transcripts' `custom-title` /
  `agent-name` lines.
- **Today**: spend by project and model, cache-hit rate, and the last 7 days.

Right-click the menu bar item for Sync, settings and Quit. Settings (also under the gear):
open at login, weekly % in the menu bar title, notifications.

## Where the numbers come from

Anthropic's limits are exact only on Anthropic's side, and every way of asking is either
rare or rate-limited. So the meter joins sparse **exact readings** with the continuous
**local logs**:

| Source | What | When |
|---|---|---|
| `~/.claude/projects/**/*.jsonl` | every Claude Code turn on this Mac: model, tokens, project | continuously (tailed every 10s) |
| statusline tap | Claude Code's own `rate_limits` (exact) | whenever a **terminal** `claude` session redraws its statusline |
| usage endpoint | same numbers as `/usage` (exact) | at most hourly; it answers 429 with `retry-after: 3600`, and needs a live Claude Code CLI login (`claude` → `/login`) |
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
resets.
