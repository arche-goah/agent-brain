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

# N CHANNELS (operator decision 2026-10-24): the default shared memory runs below exactly as
# before; then every further channel this instance is a member of (instance file
# .claude/rules/shared-memory-channels.json, read by scripts/shared_channels.py) runs this same
# check once more — its own repo, its own cursor, its label on every line. No file = one run,
# the output unchanged. A broken file is one NOT-checked line, never a silent skip.
if [[ -z "${SHARED_MEMORY_LABEL+set}" ]]; then
  _here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  . "$_here/../scripts/project-dir.sh"
  _cproj="$(resolve_project_dir "$_here")"
  _chf="${SHARED_MEMORY_CHANNELS_CONFIG:-$_cproj/.claude/rules/shared-memory-channels.json}"
  if [[ -f "$_chf" ]]; then
    SHARED_MEMORY_LABEL= bash "$_here/shared-memory-check.sh"
    _py=python3; "$_py" -c 'import sys' >/dev/null 2>&1 || _py=python
    if ! _list=$(SHARED_MEMORY_CHANNELS_CONFIG="$_chf" "$_py" "$_here/../scripts/shared_channels.py" further 2>&1); then
      echo "shared-memory channels: NOT checked - ${_list#ERROR: } (fix $_chf)"
      exit 0
    fi
    while IFS=$'\t' read -r _label _repo; do
      [[ -n "$_label" ]] || continue
      SHARED_MEMORY_LABEL="$_label" SHARED_MEMORY_REPO="$_repo" \
        SHARED_MEMORY_STATE="$_cproj/.claude-state/shared-memory-state-$_label.json" bash "$_here/shared-memory-check.sh"
    done <<<"${_list//$'\r'/}"
    exit 0
  fi
fi
# Every line names its channel; the default shared memory keeps its plain prefix.
P="shared-memory${SHARED_MEMORY_LABEL:+ [$SHARED_MEMORY_LABEL]}"
label_out() { if [[ -n "${SHARED_MEMORY_LABEL:-}" ]]; then sed "s/^shared-memory /$P /"; else cat; fi; }

REPO="${SHARED_MEMORY_REPO:-$HOME/Projects/brain-shared-memory}"
# The cursor is runtime state: it lives in .claude-state/, not in config/ (a tracked
# config/ cursor dirtied the working tree on every start — measured 2026-10-09). A brain
# that still has the old file gets it copied once, so no find is replayed or lost.
STATE_FILE="${SHARED_MEMORY_STATE:-}"
if [[ -z "$STATE_FILE" ]]; then
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/project-dir.sh"
  _proj="$(resolve_project_dir "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
  STATE_FILE="$_proj/.claude-state/shared-memory-state.json"
  _legacy="$_proj/config/shared-memory-state.json"
  if [[ ! -f "$STATE_FILE" && -f "$_legacy" ]]; then
    mkdir -p "$(dirname "$STATE_FILE")" && cp "$_legacy" "$STATE_FILE"
  fi
fi

# Not cloned. An instance that does not take part in shared memory must not be nagged about
# it every single start — but one that DOES take part must not read the missing clone as
# "nothing new" (measured 2026-10-16 on a freshly bootstrapped macOS brain: a request in
# ops/LOG.md addressed to that very machine by name sat unseen; the bootup said nothing,
# because the clone was missing and this check was silent). Taking part is read from what
# the instance already declares: SHARED_MEMORY_SELF, a collab-watch with a shared_memory
# block, or — the fresh-brain case, which declares nothing yet — the org's shared-memory
# repo existing on GitHub (SHARED_MEMORY_OWNER, passed by session-bootup.sh from the
# ecosystem owner; one `gh repo view`, only on this path).
if [[ ! -d "$REPO/.git" ]]; then
  # A further channel was declared for this instance by name: its missing clone is never quiet.
  if [[ -n "${SHARED_MEMORY_LABEL:-}" ]]; then
    echo "!! $P: NOT checked — no clone at $REPO although .claude/rules/shared-memory-channels.json lists this channel for this instance; requests addressed to it are invisible. Clone the channel's repo there."
    exit 0
  fi
  _cw="${_proj:-}/.claude/rules/collab-watch.json"
  _why=""
  # A block whose repo is still the template's <placeholder> (or empty/null) is no declaration:
  # bootstrap copies the template into every brain, so it made every fresh brain a participant
  # (2026-10-21). Same placeholder test as collab-watch-plan.py. Parsed, not grepped: a
  # reformatted block spans lines. Unreadable JSON or no Python counts as declared (loud side).
  _cw_watches() {
    local py=python3; "$py" -c 'import sys' >/dev/null 2>&1 || py=python
    "$py" -c 'import sys' >/dev/null 2>&1 || return 0
    "$py" -c '
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
sm = d.get("shared_memory") if isinstance(d, dict) else None
r = sm.get("repo") if isinstance(sm, dict) else None
sys.exit(0 if isinstance(r, str) and r.strip() and not ("<" in r and ">" in r) else 1)
' "$_cw"
  }
  if [[ -n "${SHARED_MEMORY_SELF:-}" ]]; then _why="SHARED_MEMORY_SELF is set"
  elif [[ -f "$_cw" ]] && _cw_watches; then _why="collab-watch.json watches it"
  elif [[ -n "${SHARED_MEMORY_OWNER:-}" ]] && command -v gh >/dev/null 2>&1 \
       && gh repo view "$SHARED_MEMORY_OWNER/$(basename "$REPO")" --json name >/dev/null 2>&1; then
    _why="$SHARED_MEMORY_OWNER/$(basename "$REPO") exists"
  fi
  [[ -n "$_why" ]] && echo "!! shared-memory: NOT checked — no clone at $REPO although this instance takes part ($_why); requests addressed to it are invisible. Clone: gh repo clone ${SHARED_MEMORY_OWNER:-<owner>}/$(basename "$REPO") $REPO"
  exit 0
fi

# Offline or fetch failure — ONE line saying the check did not run. The marker only
# advances on success, so nothing is lost for the next start; but silence here read as
# "nothing new" for a whole session (measured 2026-09-22: every network line of the
# bootup missing, three foreign commits incl. a merge OK unseen until the operator asked).
# A check that could not look must never look like a check that found nothing.
if ! git -C "$REPO" fetch -q origin main 2>/dev/null; then
  echo "$P: NOT checked - fetch failed (offline?). Retry: bash core/helpers/shared-memory-check.sh"
  exit 0
fi

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

# OPEN REQUESTS (2026-10-05) — independent of the cursor. The cursor moves when a start
# SHOWS an entry, not when anyone answers it: measured, three requests addressed to this
# instance were shown once, never relayed, and every later start was silent. So every start
# lists what is addressed to us by name and not yet answered, new or not.
open_requests() {
  local inbox py
  # Inside the bootup, scripts/open-items.py lists these (with PRs and a repeat counter) as
  # the ONE open list (2026-10-07). Two lists of the same items are noise, and noise is what
  # a first reply learns to skim. Run by hand, this check still lists them itself.
  [[ "${OPEN_ITEMS_IN_BOOTUP:-}" == 1 ]] && return 0
  inbox="$(dirname "${BASH_SOURCE[0]:-$0}")/../scripts/shared-memory-inbox.py"
  py=python3
  "$py" -c 'import sys' >/dev/null 2>&1 || py=python
  [[ -f "$inbox" ]] && "$py" -c 'import sys' >/dev/null 2>&1 || return 0
  "$py" "$inbox" --open --repo "$REPO" --to "$REMOTE_HEAD" 2>/dev/null | label_out
}

# Already current. Clean is ONE line, not silence (operator order 2026-10-05: "at least
# tell me 'nothing new'") — a start that prints nothing cannot be told apart from a check
# that never ran. The earlier rule "a clean check is silence" was right for briefing prose,
# wrong for a carrier the operator relies on to know the channel is alive.
if [[ "$LAST_SEEN" == "$REMOTE_HEAD" ]]; then
  # "nothing new" is about COMMITS only — it never means "nothing open" (2026-10-07: a first
  # reply read it that way and dropped nine open requests). The open list follows separately.
  echo "$P: nothing new since last start (about commits only — open points are listed separately, new or not)"
  open_requests
  exit 0
fi

COUNT=$(git -C "$REPO" rev-list --count "$LAST_SEEN..$REMOTE_HEAD" -- . 2>/dev/null)
# `paste -d ', '` looks like it joins with ", " and does not: -d takes a LIST of
# single delimiter characters, cycled per line, so it alternates comma and space
# between lines (measured 2026-08-16: "a.md,b.md c.md,d.md"). tr+sed joins correctly.
FILES=$(git -C "$REPO" diff --name-only "$LAST_SEEN" "$REMOTE_HEAD" -- . 2>/dev/null \
  | grep -v '^INDEX\.md$' | head -5 | tr '\n' '|' | sed 's/|/, /g; s/, $//')
# No git author names here (2026-09-25): two parties push under one account, so `%an`
# names accounts, not parties — the watcher learned that on 2026-08-22. Who sent what is
# the inbox's job below, from the `von:` fields and LOG headings.
if [[ "$COUNT" == "1" ]]; then
  echo "$P: 1 new commit since last start — ${FILES:-see git log}"
else
  echo "$P: ${COUNT:-?} new commits since last start — ${FILES:-see git log}"
fi

# FRESHNESS BY TOPIC (operator order 2026-09-13). The commit count above says that
# SOMETHING moved; it does not say what a session working on grandMA3 or the core needs
# to read. The register carries a date per entry since the same day, and the generator
# can be asked `--since`. Keyed on the date of the last successful check — a session that
# closed and reopened the same day sees today's entries again, which is the cheap side
# of the error. One generator call, one git pass; silence when it has nothing to add.
SINCE_DAY=""
if [[ -f "$STATE_FILE" ]]; then
  SINCE_DAY=$(grep -o '"lastCheckedAt" *: *"[^"]*"' "$STATE_FILE" 2>/dev/null \
    | sed -E 's/.*"([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/')
fi
GEN="$(dirname "${BASH_SOURCE[0]:-$0}")/../scripts/shared-memory-index.py"
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
if [[ -n "$SINCE_DAY" && -f "$GEN" ]] && "$PY" -c 'import sys' >/dev/null 2>&1; then
  # --ref: this check only fetched; the new entries are in REMOTE_HEAD, not on disk yet.
  FRESH=$("$PY" "$GEN" --repo "$REPO" --since "$SINCE_DAY" --ref "$REMOTE_HEAD" 2>/dev/null)
  # Per-topic tally from the entry lines (`- <date> [topic] …`); the generator's own count
  # line is the total. awk, not a second generator run per topic.
  BY_TOPIC=$(printf '%s\n' "$FRESH" | awk '/^- /{ if (match($0, /\[[a-z0-9-]+\]/)) t[substr($0, RSTART+1, RLENGTH-2)]++ }
    END { for (k in t) printf "%s %d, ", k, t[k] }' | sed 's/, $//')
  TOTAL=$(printf '%s\n' "$FRESH" | sed -n 's/^since [0-9-]*: \([0-9]*\) entr.*/\1/p')
  if [[ -n "$TOTAL" && "$TOTAL" != "0" ]]; then
    echo "$P: $TOTAL entr$([[ "$TOTAL" == 1 ]] && echo y || echo ies) dated since $SINCE_DAY — ${BY_TOPIC:-see --since} (list: core/scripts/shared-memory-index.py --since $SINCE_DAY${SHARED_MEMORY_LABEL:+ --repo $REPO} [--topic TOPIC])"
  fi
fi

# THE INBOX (operator order 2026-09-25). Count and topic tally say THAT something moved;
# what was addressed to this side sank unless the operator said "read it". The inbox
# prints sender plus the author's own heading/description per entry, filtered on
# SHARED_MEMORY_SELF — the main information lands in the startup message itself.
INBOX="$(dirname "${BASH_SOURCE[0]:-$0}")/../scripts/shared-memory-inbox.py"
if [[ -f "$INBOX" ]] && "$PY" -c 'import sys' >/dev/null 2>&1; then
  "$PY" "$INBOX" --repo "$REPO" --from "$LAST_SEEN" --to "$REMOTE_HEAD" 2>/dev/null | label_out
fi
open_requests

write_state
