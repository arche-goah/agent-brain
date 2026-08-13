# core/helpers — hook scripts (state of F2 cleanup 2026-07-29, path after core split 2026-08-04)

Everything here is wired up as a hook (`.claude/settings.json` hooks) — don't put
anything else here; ghost hooks were an audit finding (claude-flow import, 19 files
deleted, git history has them). Two exceptions: `statusline.cjs` (not a hook, table
below, installed at USER level via `scripts/install-statusline.sh`) and
`run-record.sh` (helper for scheduled jobs, called from launchers).

| Script | Event | Purpose |
|--------|-------|---------|
| session-bootup.sh | SessionStart | fast local sanity check (git/memory/settings/symlinks/brain-scan/tasks) |
| session-closing.sh | SessionEnd | HANDOFF.md with real git data + line in docs/maintenance/session-log.md |
| memory-sync.cjs | SessionStart/SessionEnd/PreCompact | auto-memory <-> docs/memory-snapshot sync |
| file-guard.cjs | PreToolUse (Edit/Write) | protects sensitive files + branch gate: edits in a core checkout only on a feature branch (pin/main blocks) |
| mechanism-guard.cjs | PreToolUse (Bash) | blocks known ad-hoc shortcuts; rules are instance data (`.claude/rules/mechanism-rules.json`) |
| secret-guard.cjs | PreToolUse (Read/Edit/Write/Bash) | blocks secret channels into context/repo; patterns instance-extensible (`.claude/rules/secret-patterns.json`) |
| freshness-gate.cjs | PreToolUse (Workflow) | repeat-run rule carrier: fresh completed run of the same workflow → read artifacts instead of relaunching; thresholds instance data (`.claude/rules/freshness-gate.json`) |
| junk-cleaner.cjs | PostToolUse (Bash) | cleans up junk files |
| stop-verifier.cjs | Stop | verification reminder |
| notify.cjs | PostToolUse (Agent/Task) + Notification | sound on agent end / permission question |
| statusline.cjs | statusLine (NOT a hook; user-level `~/.claude/settings.json`) | footer: model, 5h/7d rate-limit remaining with reset countdown, context % — install: `scripts/install-statusline.sh` |

Active session close: skill `session-close` (SessionEnd is only a best-effort fallback).
