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

# 2) shared memory — the WRITE side of the cross-instance class (operator order
# 2026-09-13: read and write from bootup to closing, as one class). The close skill
# already asks, in prose, whether a finding of this session reaches past this machine.
# What was never mechanical: whether what WAS written actually left the machine. Measured
# 2026-08-17: three merged PRs corrected a claim the shared record still stated as open,
# and the shared entry was written only after the operator asked. An entry that is
# committed but not pushed — or edited and not committed — is exactly that failure with
# better intentions. Reported as a FAIL line, not swallowed: the skill reads this output.
SM_REPO="${SHARED_MEMORY_REPO:-$HOME/Projects/brain-shared-memory}"
sm_line=""
if [ -d "$SM_REPO/.git" ]; then
  sm_dirty=$(git -C "$SM_REPO" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  sm_unpushed=$(git -C "$SM_REPO" log --branches --not --remotes --oneline 2>/dev/null | wc -l | tr -d ' ')
  sm_line="shared=dirty:${sm_dirty},unpushed:${sm_unpushed}"
  if [ "${sm_dirty:-0}" -gt 0 ] || [ "${sm_unpushed:-0}" -gt 0 ]; then
    echo "FAIL shared-memory: ${sm_dirty} uncommitted file(s), ${sm_unpushed} unpushed commit(s) in $SM_REPO — nothing in there has reached the other instances; commit and push before the session ends, or say why not"
    printf '\n## Shared memory: NOT delivered\n%s uncommitted, %s unpushed — the other instances read none of it.\n' \
      "$sm_dirty" "$sm_unpushed" >> .claude/HANDOFF.md
  fi
fi

# 3) session-log: one line per session end (lightweight change log)
# Dedupe: both the skill and the SessionEnd hook call in here — don't append an identical line twice.
log=docs/maintenance/session-log.md
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
last=$(git log --oneline -1 2>/dev/null)
entry="$(git branch --show-current 2>/dev/null) | uncommitted=$dirty${sm_line:+ | $sm_line} | last: $last"
tail -5 "$log" 2>/dev/null | grep -qF "$entry" || echo "- $TS | $entry" >> "$log"
