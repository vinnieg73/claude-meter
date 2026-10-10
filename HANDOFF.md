# Claude Meter: handoff

Updated 2026-10-10 by Claude, from the Utilities project thread.

## Status

v0.9.7 (build 20, commit 7dfbb2d) is on GitHub (vinnieg73/claude-meter, private) and installed in
`~/Applications`. Replay passes. The repo's CLAUDE.md limits work to bug fixes; features need
Vinnie's OK and a dated exception note there.

## Done recently

- v0.9.7: 12 audit fixes. Sonnet 5.5 cache reads at $0.10. Fast mode only on Opus 5.5, Opus 5 and Opus 4.8. The probe strips API, Bedrock, Vertex and Foundry env vars, merges rate_limit_events, and catches expired-token sign-outs. The `CLAUDE_CONFIG_DIR` lookup runs off the main thread with 3 retries. A runaway's row is pinned in Burning now. The week chart scales correctly around an early reset. Replay is stricter and anchored to the newest reading.
- v0.9.6: the model moved to the row tooltip so names fit. Tags read "· 4m". "cold in <1m".
- v0.9.5: rows are named by the desktop app's thread title. Rows that share a name get a last-ran tag.
- Replay: the weekly accuracy floor scales with how many days the week's readings span.

## Next steps

1. Oct 15: a scheduled read-only check re-runs replay after the Oct 7 early-reset data ages out.
2. Nov 4: a scheduled check confirms the weekly reset after DST ended.

## Open decisions (Vinnie's)

- A weekly scheduled read-only replay that reports PASS or FAIL.
- An alert when exact readings stop arriving, for example after a Claude Code update breaks the probe. This is a small feature, so it needs an OK.
- Low-priority audit leftovers are listed in the audit report (`claude-meter-audit-2026-10-09` in the project files).

## Gotchas

- Before calling anything done, run `./scripts/replay.sh` (must PASS). For view changes, also run `scripts/render-all.sh <dir>` and check light and dark. Replay doesn't exercise `Probe.swift`, so after an install confirm `ClaudeMeter --status` shows a fresh probe reading.
- `scripts/build.sh --install` kills and relaunches the menu bar app. A plain `build.sh` only writes `build/`.
- Releases bump `Resources/Info.plist` (version and build) and use `vX.Y.Z: …` commit messages.
- Vinnie's Mac needs his own typed go-ahead for each commit and push.
- Tried and rejected: a 5-minute hold on the probe gate after a reset. It fails replay by blocking probes after real window openings.
- The 5-hour % weights turns by API list price (`Pricing.swift`). A new model id falls back to the newest price in its family. Update the table when models change.
- Desktop thread titles come from `~/Library/Application Support/Claude/claude-code-sessions/*/local_*.json`, an undocumented format. If it changes, rows quietly fall back to folder names.
- Keep the folder at `~/Code/Claude Meter`. Scheduled checks and Claude Code history depend on that path.
