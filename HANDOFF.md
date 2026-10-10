# Claude Meter: handoff

Updated 2026-10-10 by Claude, from the Utilities project thread (after v0.9.8).

## Status

v0.9.9 (build 22) is on GitHub (vinnieg73/claude-meter, private) and installed in `~/Applications`. Replay passes. The repo's CLAUDE.md limits work to bug fixes; features need
Vinnie's OK and a dated exception note there.

## Done recently

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

- Low-priority audit leftovers are listed in the audit report (`claude-meter-audit-2026-10-09` in the project files).

## Gotchas

- Before calling anything done, run `./scripts/replay.sh` (must PASS). For view changes, also run `scripts/render-all.sh <dir>` and check light and dark. Replay doesn't exercise `Probe.swift`, so after an install confirm `ClaudeMeter --status` shows a fresh probe reading.
- `scripts/build.sh --install` kills and relaunches the menu bar app. A plain `build.sh` only writes `build/`.
- Releases bump `Resources/Info.plist` (version and build) and use `vX.Y.Z: …` commit messages.
- Vinnie's Mac needs his own typed go-ahead for each commit and push.
- The Oct 15 check's cap ranges were updated for v0.9.7's lower caps (about $144 / $1.1k). If caps move again, update `~/.claude/scheduled-tasks/claude-meter-oct-15-check`.
- Known limit: with no 5-hour window open by this Mac's reckoning (the last reading's window ended and nothing was logged here since), the meter can't probe, because a probe would open a window. Use elsewhere then shows up only at the next message on this Mac (Sync won't probe either, for the same reason).
- Tried and rejected: a 5-minute hold on the probe gate after a reset. It fails replay by blocking probes after real window openings.
- The 5-hour % weights turns by API list price (`Pricing.swift`). A new model id falls back to the newest price in its family. Update the table when models change.
- Desktop thread titles come from `~/Library/Application Support/Claude/claude-code-sessions/*/local_*.json`, an undocumented format. If it changes, rows quietly fall back to folder names.
- Keep the folder at `~/Code/Claude Meter`. Scheduled checks and Claude Code history depend on that path.
