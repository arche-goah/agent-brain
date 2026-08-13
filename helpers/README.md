# core/helpers — hook scripts (state of F2 cleanup 2026-07-29, path after core split 2026-08-04)

Only these 7 are wired up as hooks (`.claude/settings.json` hooks) — don't put anything
else here; ghost hooks were an audit finding (claude-flow import, 19 files deleted,
git history has them). Only exception: `statusline.cjs` — not a hook, but the
statusline (table below), installed at USER level via `scripts/install-statusline.sh`.

| Script | Event | Purpose |
|--------|-------|---------|
| session-bootup.sh | SessionStart | fast local sanity check (git/memory/settings/symlinks/brain-scan/tasks) |
| session-closing.sh | SessionEnd | HANDOFF.md with real git data + line in docs/maintenance/session-log.md |
| memory-sync.cjs | SessionStart/SessionEnd/PreCompact | auto-memory <-> docs/memory-snapshot sync |
| file-guard.cjs | PreToolUse (Edit/Write) | protects sensitive files + branch gate: edits in a core checkout only on a feature branch (pin/main blocks) |
| junk-cleaner.cjs | PostToolUse (Bash) | cleans up junk files |
| stop-verifier.cjs | Stop | verification reminder |
| notify.cjs | PostToolUse (Agent/Task) + Notification | sound on agent end / permission question |
| statusline.cjs | statusLine (NOT a hook; user-level `~/.claude/settings.json`) | footer: model, 5h/7d rate-limit remaining with reset countdown, context % — install: `scripts/install-statusline.sh` |

Active session close: skill `session-close` (SessionEnd is only a best-effort fallback).
