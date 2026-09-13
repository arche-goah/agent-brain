#!/usr/bin/env bash
# Session-Closing — HANDOFF.md with REAL data (git) + session-log line.
# Two callers, one script:
#   session-close skill:  session-closing.sh --pre-commit [--session <id>]   BEFORE the close commit
#   SessionEnd hook:      session-closing.sh                                 at process end, JSON on stdin
# Portable bash (no zsh): Windows/Git-Bash has no zsh, the hook never ran there.
# The body was always POSIX — only the shebang and the hook wiring forced zsh.
# Replaces handoff-generator ({To be filled} templates) + dead metrics (audit 2026-07-29).
# Semantic memory is handled by memory-sync.cjs export (separate hook, stays).
#
# INVARIANT (2026-09-13, measured on two machines): after the close commit no hook touches
# a tracked file. The old line carried `last: <commit>` and `uncommitted=N`, so the hook's
# line after the commit was different BY CONSTRUCTION from the line the skill had written
# before it, the dedupe never matched, and every session started with a dirty tree — on
# the second machine `git pull --ff-only` then failed on exactly that file. Now:
#   - `--pre-commit` (skill step, before its commit) writes the line WITHOUT post-commit
#     state — the commit that carries the line IS the close commit, nothing is lost — and
#     leaves an UNTRACKED stamp `.claude-state/session-close.stamp` (the template
#     .gitignore excludes `.claude-state/`) holding the session id it was given.
#   - the hook run consumes the stamp: same id (or a stamp without one) = this session's
#     line is already written, the log is not touched; the stamp is removed either way, so
#     a stamp from a session that died after its skill step cannot silence a later one.
#   - no stamp = the session ended without the skill (hard kill, topic change): the line is
#     written here WITH `uncommitted=`/`last:`, and a dirty tree is the honest state.
# Why a stamp and not only a marker in the line: the skill side has no guaranteed session
# id (`${CLAUDE_SESSION_ID}` is substituted into skill text by newer harnesses, older ones
# leave it empty), the hook side always has one on stdin. The stamp works without an id;
# the id, when present, closes the one remaining hole (two sessions in one repo ending
# together). Two limits kept on purpose: this script never commits (the commit policy is
# instance knowledge), and the hook fallback stays (a session that dies without the skill
# still leaves a trace).
set -u
R="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$R" || exit 0
TS=$(date '+%F %T')

pre_commit=0; sid=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pre-commit) pre_commit=1 ;;
    --session) sid="${2:-}"; shift ;;
  esac
  shift
done
stamp=.claude-state/session-close.stamp
if [ "$pre_commit" -eq 0 ] && [ ! -t 0 ]; then
  # SessionEnd hook input: {"session_id": "...", ...}. Bounded read — a caller that keeps
  # stdin open must not hang a 10 s hook.
  input=""; IFS= read -r -t 3 -d '' input || true
  sid=$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

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

# 3) session-log: one line per session (lightweight change log) — see the header.
log=docs/maintenance/session-log.md
branch=$(git branch --show-current 2>/dev/null)
if [ "$pre_commit" -eq 1 ]; then
  mkdir -p .claude-state
  printf '%s\n' "$sid" > "$stamp"
  echo "- $TS | $branch | close${sm_line:+ | $sm_line}" >> "$log"
  exit 0
fi
if [ -f "$stamp" ]; then
  stamped=$(head -1 "$stamp" 2>/dev/null)
  rm -f "$stamp"
  if [ -z "$stamped" ] || [ "$stamped" = "$sid" ]; then
    exit 0   # this session's line is already in the log (and in the close commit)
  fi
fi
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
last=$(git log --oneline -1 2>/dev/null)
entry="$branch | hook-end | uncommitted=$dirty${sm_line:+ | $sm_line} | last: $last"
tail -5 "$log" 2>/dev/null | grep -qF "$entry" || echo "- $TS | $entry" >> "$log"
