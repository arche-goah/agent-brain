#!/usr/bin/env bash
# Session-Closing — SessionEnd hook: HANDOFF.md with REAL data (git) + session-log line.
# Portable bash (no zsh): Windows/Git-Bash has no zsh, the hook never ran there.
# The body was always POSIX — only the shebang and the hook wiring forced zsh.
# Replaces handoff-generator ({To be filled} templates) + dead metrics (audit 2026-07-29).
# Semantic memory is handled by memory-sync.cjs export (separate hook, stays).
set -u
R="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$R" || exit 0
TS=$(date '+%F %T')

# 1) HANDOFF.md — only evidenced facts, no placeholders
{
  echo "# Session Handoff (auto-generated, real data only)"
  echo "> $TS by core/helpers/session-closing.sh — interpretation/next steps: read memory + git log."
  echo
  echo '## Git'
  echo '```'
  git status --short --branch 2>/dev/null | head -30
  echo '```'
  echo '## Last commits'
  echo '```'
  git log --oneline -5 2>/dev/null
  echo '```'
  unpushed=$(git log --branches --not --remotes --oneline 2>/dev/null | wc -l | tr -d ' ')
  echo "## Unpushed: $unpushed commits"
} > .claude/HANDOFF.md

# 2) session-log: one line per session end (lightweight change log)
# Dedupe: both the skill and the SessionEnd hook call in here — don't append an identical line twice.
log=docs/maintenance/session-log.md
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
last=$(git log --oneline -1 2>/dev/null)
entry="$(git branch --show-current 2>/dev/null) | uncommitted=$dirty | last: $last"
tail -5 "$log" 2>/dev/null | grep -qF "$entry" || echo "- $TS | $entry" >> "$log"
