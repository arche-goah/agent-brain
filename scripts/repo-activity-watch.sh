#!/usr/bin/env bash
# repo-activity-watch.sh — one stdout line per collaboration EVENT in a set of GitHub repos:
# new pull requests, merges, and comments (conversation AND inline review comments, also on
# pull requests that are already merged). Built for the Monitor tool (`persistent: true`);
# normally started by scripts/collab-watch.sh under scripts/watch-supervisor.sh.
#
#   GH_WATCH_REPOS="<owner>/<a> <owner>/<b>" repo-activity-watch.sh [interval_s|once|status|disarm]
#
# WHY COMMENTS AND MERGES, NOT ONLY THE PR LIST (measured on the proving instance): a watch
# that polled `gh pr list` saw only the EXISTENCE of open pull requests. A collaborator then
# posted a retest result as a comment on an already merged PR — the normal case once work is
# under way: artifacts appear once, the talk happens afterwards — and the watch stayed
# correctly silent and blind. Later the same shape again: the other party merged our PR
# without a comment, and a merged PR leaves the open list instead of entering it. A watch
# polls the channel the EVENT appears on, not the one the artifact does.
#
# Env:
#   GH_WATCH_REPOS          required — owner/name tokens
#   GH_SELF_LOGIN           login NOT to report; default "-" (matches nobody). Leave it: the
#                           operator's machines share one account, a self filter swallows
#                           the other own machine. See references/watch-lessons.md.
#   GH_ONLY_LOGINS          report only these logins ("-" or unset = everyone)
#   REPO_ACTIVITY_STATE_DIR cursor + lock directory (default $CLAUDE_PROJECT_DIR/.claude-state)
#   REPO_ACTIVITY_TAG       separates several watches of this script (own cursor, own lock)
#   COLLAB_WATCH_CLONE_ROOT where local clones live (default $HOME/Projects, CONVENTIONS §13)
#
# The cursor is a FILE: whatever happens while nothing runs is reported at the next start.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python

SELF="${GH_SELF_LOGIN:--}"
ONLY="${GH_ONLY_LOGINS:--}"
[[ -n "$ONLY" ]] || ONLY="-"
STATE_DIR="${REPO_ACTIVITY_STATE_DIR:-${CLAUDE_PROJECT_DIR:-.}/.claude-state}"
TAG="${REPO_ACTIVITY_TAG:+-$REPO_ACTIVITY_TAG}"
CURSOR="$STATE_DIR/repo-activity${TAG}-cursor.txt"
LOCK="$STATE_DIR/repo-activity${TAG}.pid"
CLONE_ROOT="${COLLAB_WATCH_CLONE_ROOT:-$HOME/Projects}"
MODE="${1:-60}"
mkdir -p "$STATE_DIR"

lock_owner_alive() {
  [[ -f "$LOCK" ]] || return 1
  local pid; pid=$(cat "$LOCK" 2>/dev/null)
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

case "$MODE" in
  status) if lock_owner_alive; then echo "armed: pid $(cat "$LOCK")"; else echo "not armed"; fi; exit 0 ;;
  disarm) rm -f "$LOCK"; echo "disarmed"; exit 0 ;;
  once) INTERVAL=0 ;;
  *[!0-9]*|"") echo "usage: $0 [interval_s|once|status|disarm]" >&2; exit 64 ;;
  *) INTERVAL="$MODE" ;;
esac

read -r -a REPOS <<<"${GH_WATCH_REPOS:-}"
if [[ ${#REPOS[@]} -eq 0 ]]; then
  echo "ERROR: GH_WATCH_REPOS is empty — name the repos to watch (owner/name)"; exit 64
fi
if [[ "$ONLY" != "-" ]]; then
  echo "NOTE: include filter active — only $ONLY is reported; anything else is dropped and NOT replayed later"
fi

# Claim and check in ONE step: `noclobber` makes the redirect fail if the file exists
# (O_EXCL). Check-then-write leaves a window in which two sessions both pass the check.
claim() { ( set -o noclobber; echo $$ > "$LOCK" ) 2>/dev/null; }
if ! claim; then
  if lock_owner_alive; then
    echo "already armed: lock $LOCK names live pid $(cat "$LOCK") — skipping duplicate watcher (a live pid is a process, not proof of a session)"
    exit 0
  fi
  rm -f "$LOCK"   # owner gone without its trap (kill -9, crash, reboot)
  claim || { echo "ERROR: cannot claim lock $LOCK"; exit 1; }
fi
# Release only a lock that STILL names this process — an unconditional rm deletes the lock
# a later session legitimately took over, and the next one arms a second, invisible watcher.
trap 'if [[ "$(cat "$LOCK" 2>/dev/null)" == "$$" ]]; then rm -f "$LOCK"; fi' EXIT
trap 'exit 0' TERM INT   # untrapped, TERM kills bash without running the EXIT trap above

# A missing cursor is LOUD, never a silent "everything is old".
if [[ ! -s "$CURSOR" ]]; then
  seed=$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
      || date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
      || date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "$seed" > "$CURSOR"
  echo "NOTE: no cursor — starting from $seed (earlier activity is NOT reported)"
fi

# Lines from the filter: "CURSOR <ts>" moves NEWEST, "<branch>\t<text>" gets the local-branch
# mark, anything else is printed as is. Runs in THIS shell (fed by process substitution),
# so NEWEST survives the loop.
emit() {
  local clone="$1" line br text
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in
      "") ;;
      "CURSOR "*) [[ "${line#CURSOR }" > "$NEWEST" ]] && NEWEST="${line#CURSOR }" ;;
      *$'\t'*)
        br="${line%%$'\t'*}"; text="${line#*$'\t'}"
        # The account login cannot tell this session, a parallel session on this machine
        # and the operator's other machine apart. The branch can: a PR whose head branch is
        # a LOCAL branch in this machine's clone was made here.
        if [[ -n "$br" ]] && git -C "$clone" rev-parse -q --verify "refs/heads/$br" >/dev/null 2>&1; then
          text="$text — branch is LOCAL in this machine's clone: a parallel session here (or checked out by hand), not another machine"
        fi
        printf '%s\n' "$text" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
}

PARENT=$PPID
gh_down=0
while true; do
  SINCE=$(tr -d '\r\n' < "$CURSOR")
  NEWEST="$SINCE"
  # Reachability first: a watcher whose every call fails (auth expired, network gone) prints
  # nothing and looks exactly like a quiet one. Said once per outage, not every round.
  if ! gh api rate_limit >/dev/null 2>&1; then
    [[ $gh_down -eq 0 ]] && echo "WATCH-ERROR: gh cannot reach GitHub — this watch is BLIND until it can (repos: ${REPOS[*]})"
    gh_down=1
  else
    [[ $gh_down -eq 1 ]] && echo "NOTE: gh reachable again — events since $SINCE follow"
    gh_down=0
    for full in "${REPOS[@]}"; do
      clone="$CLONE_ROOT/${full#*/}"
      for kind in issues/comments pulls/comments; do
        emit "$clone" < <(gh api "repos/$full/$kind?since=$SINCE&per_page=50" 2>/dev/null \
          | "$PY" "$HERE/repo-activity-filter.py" comments "$full" "$SINCE" "$SELF" "$ONLY")
      done
      emit "$clone" < <(gh pr list --repo "$full" --state open --limit 50 \
          --json number,title,author,createdAt,headRefName 2>/dev/null \
        | "$PY" "$HERE/repo-activity-filter.py" open "$full" "$SINCE" "$SELF" "$ONLY")
      emit "$clone" < <(gh pr list --repo "$full" --state merged --limit 50 \
          --json number,title,mergedBy,mergedAt,headRefName 2>/dev/null \
        | "$PY" "$HERE/repo-activity-filter.py" merged "$full" "$SINCE" "$SELF" "$ONLY")
    done
    [[ "$NEWEST" != "$SINCE" ]] && echo "$NEWEST" > "$CURSOR"
  fi
  [[ "$INTERVAL" -eq 0 ]] && exit 0
  # A watcher outlives its session unless it checks: when the process that started it is
  # gone, exit (the EXIT trap frees the lock for the next arm).
  for (( slept = 0; slept < INTERVAL; slept += 5 )); do
    sleep 5 & wait $!   # backgrounded: a TERM is handled at once, not after the sleep
    kill -0 "$PARENT" 2>/dev/null || exit 0
  done
done
