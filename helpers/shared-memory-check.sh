#!/usr/bin/env bash
# Level 1 of the shared-memory awareness pair: at SESSION START, report commits that
# other instances or collaborators pushed to the shared-memory repo since this
# instance last looked. Level 2 (scripts/shared-memory-watch.sh) covers the time
# WHILE a session runs.
#
# WHY BOTH LEVELS EXIST: a shared repo that is only read when someone remembers to
# read it is a "shared" repo in name only. The failure is silent by construction —
# nothing about a stale checkout looks different from a quiet one. Level 1 closes the
# gap across session boundaries, level 2 within a session; between them there is no
# window in which a foreign commit can sit unnoticed for longer than one poll.
#
# THE CURSOR IS PER INSTANCE AND LIVES IN THE INSTANCE. The shared repo never carries
# per-instance state (same rule as everywhere: shared carries facts, not whose eyes
# have seen them). Default location is the instance's config/; overridable so tests
# and unusual layouts do not have to touch the real one.
#
# Grew in one brain (2026-08-16) as an instance-local hook, proven there in daily use,
# folded into the core on 2026-08-18 when a second machine needed the same thing —
# which is the moment a mechanism stops being instance knowledge.
set -uo pipefail

REPO="${SHARED_MEMORY_REPO:-$HOME/Projects/brain-shared-memory}"
STATE_FILE="${SHARED_MEMORY_STATE:-${CLAUDE_PROJECT_DIR:-.}/config/shared-memory-state.json}"

# Not cloned (fresh machine, onboarding not done) — silent. An instance that does not
# take part in shared memory must not be nagged about it every single start.
[[ -d "$REPO/.git" ]] || exit 0

# Offline or fetch failure — silent, no false alarm. Nothing is lost: the marker only
# advances on success, so the missed commits surface at the next successful check.
git -C "$REPO" fetch -q origin main 2>/dev/null || exit 0

REMOTE_HEAD=$(git -C "$REPO" rev-parse origin/main 2>/dev/null) || exit 0
[[ -n "$REMOTE_HEAD" ]] || exit 0

LAST_SEEN=""
if [[ -f "$STATE_FILE" ]]; then
  LAST_SEEN=$(grep -o '"lastSeenSha" *: *"[^"]*"' "$STATE_FILE" 2>/dev/null | sed -E 's/.*"([^"]*)"$/\1/')
fi

write_state() {
  mkdir -p "$(dirname "$STATE_FILE")"
  printf '{\n  "lastSeenSha": "%s",\n  "lastCheckedAt": "%s"\n}\n' \
    "$REMOTE_HEAD" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_FILE"
}

# First run: set the baseline silently. Otherwise the first start after installing
# this would announce the entire repo history as "new" — noise, not a finding.
if [[ -z "$LAST_SEEN" ]]; then
  write_state
  exit 0
fi

# Already current. A check that came back clean is silence, not a line.
if [[ "$LAST_SEEN" == "$REMOTE_HEAD" ]]; then
  exit 0
fi

COUNT=$(git -C "$REPO" rev-list --count "$LAST_SEEN..$REMOTE_HEAD" -- . 2>/dev/null)
# `paste -d ', '` looks like it joins with ", " and does not: -d takes a LIST of
# single delimiter characters, cycled per line, so it alternates comma and space
# between lines (measured 2026-08-16: "a.md,b.md c.md,d.md"). tr+sed joins correctly.
FILES=$(git -C "$REPO" diff --name-only "$LAST_SEEN" "$REMOTE_HEAD" -- . 2>/dev/null \
  | grep -v '^INDEX\.md$' | head -5 | tr '\n' '|' | sed 's/|/, /g; s/, $//')
AUTHORS=$(git -C "$REPO" log --format='%an' "$LAST_SEEN..$REMOTE_HEAD" -- . 2>/dev/null \
  | sort -u | tr '\n' '|' | sed 's/|/, /g; s/, $//')

if [[ "$COUNT" == "1" ]]; then
  echo "shared-memory: 1 new commit since last start (${AUTHORS:-unknown}) — ${FILES:-see git log}"
else
  echo "shared-memory: ${COUNT:-?} new commits since last start (${AUTHORS:-unknown}) — ${FILES:-see git log}"
fi

write_state
