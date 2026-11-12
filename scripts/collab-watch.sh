#!/usr/bin/env bash
# collab-watch.sh — THE collaboration watch: arms every configured channel at once and
# merges their events onto this script's stdout, so ONE Monitor call covers the lot:
#
#   Monitor({ command: "bash core/scripts/collab-watch.sh", timeout_ms: 1800000 })
#   bash core/scripts/collab-watch.sh --dry-run      # print the plan, arm nothing
#
# Channels (which ones, which repos, which intervals = INSTANCE data, never in this file):
#   shared memory      scripts/shared-memory-watch.sh  — commits from other instances/parties,
#                      once for the default shared memory and once per further channel this
#                      instance is a member of ($SHARED_MEMORY_CHANNELS_CONFIG, default
#                      <instance>/.claude/rules/shared-memory-channels.json; finds carry `[<label>]`)
#   repo watches       scripts/repo-activity-watch.sh  — PRs, merges, comments, review comments
#   parallel sessions  scripts/parallel-sessions-watch.sh — sessions joining/leaving this repo
# Each runs under scripts/watch-supervisor.sh, so a child that dies says so.
#
# Config: $COLLAB_WATCH_CONFIG, default <instance>/.claude/rules/collab-watch.json
#         (template: templates/rules-instance/collab-watch.json)
# Scope:  $COLLAB_WATCH_SCOPE = all (default) | peers | <party label/id/login>
# Topics: $COLLAB_WATCH_TOPICS = space-separated topics this session owns (e.g. "grandma3 grandma").
#         A topic widens the party scope, it never narrows it: a repo watch whose TAG is a topic
#         reports every login, and a shared-memory find that touches a `<topic>/` folder passes
#         whoever wrote it. WHY (measured 2026-10-11): a session scoped to one collaborator owned
#         the grandMA work; the party filter dropped every PR event under the operator's own
#         login — the other machine's test fix and its "please review" — because one login
#         carries both of the operator's machines and a login filter cannot keep one of them.
# Show:   $COLLAB_WATCH_SHOW = an extended regex: the event lines THIS session is told (its stdout). NOTE:/ERROR:
#         lines always pass; events.log keeps every line, so a follower or a later holder with another filter
#         loses nothing. Empty = everything. WHY (measured 2026-11-12, 3D session): the session holding the
#         watch is the one it wakes - about 14 grandMA and core events reached a 3D conversation, the
#         operator (translated): "none of this interests me here". The party scope cannot say "only my topic".
# State:  $COLLAB_WATCH_STATE, default <instance>/.claude-state/collab-watch — cursors AND
#         locks of every channel. Its own shared-memory cursor on purpose: sharing the cursor
#         of the session-start check lets ANY session's start consume a find before the
#         designated watcher reports it. Two sessions that must watch independently each set
#         their own COLLAB_WATCH_STATE (it moves the locks too, so neither is refused).
#
# Skill: skills/collab-watch/SKILL.md (procedure, handling flow, lessons).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/project-dir.sh"   # config and state must not depend on the caller's cwd
INSTANCE="$(resolve_project_dir "$HERE")"
CONFIG="${COLLAB_WATCH_CONFIG:-$INSTANCE/.claude/rules/collab-watch.json}"
SCOPE="${COLLAB_WATCH_SCOPE:-all}"
TOPICS="${COLLAB_WATCH_TOPICS:-}"
SHOW="${COLLAB_WATCH_SHOW:-}"
STATE="${COLLAB_WATCH_STATE:-$INSTANCE/.claude-state/collab-watch}"
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python

# Further shared-memory channels (scripts/shared_channels.py): each gets its own cursor
# `shared-memory-cursor-<label>.json` and its own lock dir `shared-memory-<label>/` in $STATE.
CHANNELS="${SHARED_MEMORY_CHANNELS_CONFIG:-$INSTANCE/.claude/rules/shared-memory-channels.json}"

PLAN=$("$PY" "$HERE/collab-watch-plan.py" "$CONFIG" "$SCOPE" "$CHANNELS") || exit $?
PLAN="${PLAN//$'\r'/}"
field() { awk -v k="$1" '$1 == k { $1 = ""; sub(/^ /, ""); print }' <<<"$PLAN"; }
ONLY_LOGINS=$(field SCOPE_LOGINS)
ONLY_PARTIES=$(field SCOPE_PARTIES)
SCOPE_LABEL=$(field SCOPE_LABEL)

if [[ "${1:-}" == "--dry-run" ]]; then
  printf '%s\n' "$PLAN"
  exit 0
fi

# Party filter for the shared-memory stream. Only FOUND: lines are judged; NOTE/ERROR lines
# always pass, and a find whose party could NOT be determined passes too — an unknown party
# is a finding, not noise. fflush(), or the line sits in awk's buffer and the watch looks
# silent. Applied to the WHOLE stdout, not piped onto one background job: a pipe would make
# `$!` the filter's pid, and the cleanup would kill the filter while the watch kept polling.
sm_scope_filter() {
  if [[ "$ONLY_PARTIES" != "-" ]]; then
    awk -v list="$ONLY_PARTIES" -v topics="$TOPICS" \
      'BEGIN { n = split(list, p, " "); m = split(topics, t, " ") }
       /^FOUND:/ {
         if (index($0, "unknown party")) { print; fflush(); next }
         for (i = 1; i <= n; i++) if (index($0, p[i])) { print; fflush(); next }
         for (j = 1; j <= m; j++) if (index($0, " " t[j] "/") || index($0, "," t[j] "/")) { print; fflush(); next }
         next
       }
       { print; fflush() }'
  else
    cat
  fi
}
# A repo watch whose tag is one of this session's topics reports every login.
logins_for_tag() {
  case " $TOPICS " in
    *" $1 "*) echo "-" ;;
    *) echo "$ONLY_LOGINS" ;;
  esac
}
# What this session is told: NOTE/ERROR always, event lines only when they match $COLLAB_WATCH_SHOW (grep -E).
# Applied AFTER the log, never before it: the log is every session's source.
show_filter() {
  if [[ -n "$SHOW" ]]; then
    awk -v rx="$SHOW" '/^(NOTE|ERROR):/ || $0 ~ rx { print; fflush() }'
  else
    cat
  fi
}
# Fixture seam: run only the shared-memory filter over stdin, arm nothing.
if [[ "${1:-}" == "--filter-stdin" ]]; then sm_scope_filter; exit 0; fi
if [[ "${1:-}" == "--show-stdin" ]]; then show_filter; exit 0; fi
if [[ "${1:-}" == "--logins-for" ]]; then logins_for_tag "${2:-}"; exit 0; fi

mkdir -p "$STATE"
# One watch per state dir and machine; every further session FOLLOWS it instead of being
# skipped. WHY (measured 2026-11-06): a second session armed this script, every channel
# answered "already armed by another session" and left, and the comment with a Windows
# finding on that session's own PR reached only the first session. The holder appends every
# line it reports to $EVENTS; a follower prints that file's new lines and takes over the
# watch when the holder ends. The pid file names the holder; a dead pid is a stale file.
EVENTS="$STATE/events.log"
HOLDER="$STATE/collab-watch.pid"
PARENT=$PPID
holder_alive() { local p; p=$(cat "$HOLDER" 2>/dev/null) && [[ -n "$p" && "$p" != "$$" ]] && kill -0 "$p" 2>/dev/null; }
if holder_alive; then
  echo "NOTE: collaboration watch already held by pid $(cat "$HOLDER") — following its events ($EVENTS); taking over if it ends"
  touch "$EVENTS"
  # No filter: tail alone, `$!` is its pid. With a filter: a plain pipe - a process substitution behind `&` passed no
  # line on Git Bash (portability windows-latest, train #510, 2026-11-12). `$!` is then the filter's pid; killing it
  # leaves tail to end with SIGPIPE at the next line, which the new holder writes at once (its arm note goes to the log).
  if [[ -n "$SHOW" ]]; then
    tail -n 0 -F "$EVENTS" 2>/dev/null | show_filter &
  else
    tail -n 0 -F "$EVENTS" 2>/dev/null &
  fi
  TAIL=$!
  trap 'kill "$TAIL" 2>/dev/null' EXIT
  trap 'exit 0' INT TERM
  while kill -0 "$PARENT" 2>/dev/null; do
    if ! holder_alive; then
      kill "$TAIL" 2>/dev/null
      echo "NOTE: the holder ended — this session takes over the collaboration watch"
      exec bash "${BASH_SOURCE[0]}" "$@"
    fi
    sleep "${COLLAB_WATCH_FOLLOW_POLL:-5}" & wait $!
  done
  exit 0
fi
echo "$$" > "$HOLDER"
# A log above 1 MB starts over: followers read only new lines, so nothing they need is lost.
[[ -f "$EVENTS" && $(wc -c < "$EVENTS") -gt 1048576 ]] && : > "$EVENTS"
exec > >(sm_scope_filter | tee -a "$EVENTS" | show_filter)

# A non-default state dir is invisible to helpers/watch-gate.cjs (the variable lives on the
# Monitor command, not in the hook's environment), so name it where the gate looks. Node
# reads it, so on Git Bash the path goes in Windows form (`/c/...` is no path to Node).
REGISTRY="$INSTANCE/.claude-state/collab-watch-states"
REG_PATH=$(cygpath -m "$STATE" 2>/dev/null || echo "$STATE")
if [[ "$STATE" != "$INSTANCE/.claude-state/collab-watch" ]] && ! grep -qxF "$REG_PATH" "$REGISTRY" 2>/dev/null; then
  mkdir -p "$INSTANCE/.claude-state" && echo "$REG_PATH" >> "$REGISTRY"
fi
pids=()
# Supervisors kill their own child on TERM (see watch-supervisor.sh), so killing them is
# enough — portable, no pkill.
# TERM/INT must EXIT, not only clean up: a bash trap that does not exit swallows the signal,
# and the script went on polling its parent with every supervisor already gone (measured in
# the live smoke of this script: TaskStop-style TERM left the arm process running).
cleanup() {
  for p in ${pids[@]+"${pids[@]}"}; do kill "$p" 2>/dev/null; done  # empty before the first arm: OS-22
  [[ "$(cat "$HOLDER" 2>/dev/null)" == "$$" ]] && rm -f "$HOLDER"
}
trap cleanup EXIT
trap 'exit 0' INT TERM

armed=()
# One shared-memory channel: $1 interval, $2 repo, $3 label ("" = the default shared memory,
# whose cursor and lock keep their old names). A cursor or lock shared by two channels breaks
# both: shared-memory-watch.sh refuses a cursor of another repo, and the second lock holder skips.
arm_sm() {
  local repo="${2/#\~/$HOME}" cursor="$STATE/shared-memory-cursor${3:+-$3}.json"
  local lock="$STATE${3:+/shared-memory-$3}" name="shared-memory${3:+ [$3]}" sha
  if [[ ! -s "$cursor" ]]; then
    git -C "$repo" fetch -q --no-write-fetch-head origin main 2>/dev/null
    sha=$(git -C "$repo" rev-parse origin/main 2>/dev/null)
    if [[ -z "$sha" ]]; then
      echo "ERROR: cannot read origin/main in $repo — ${name/shared-memory/shared-memory channel} NOT armed"
      return 1
    fi
    printf '{\n  "lastSeenSha": "%s",\n  "lastCheckedAt": "seeded"\n}\n' "$sha" > "$cursor"
    echo "NOTE: $name cursor seeded at ${sha:0:8} — older commits are NOT reported"
  fi
  mkdir -p "$lock"
  SHARED_MEMORY_REPO="$repo" SHARED_MEMORY_STATE="$cursor" SHARED_MEMORY_LOCK_DIR="$lock" SHARED_MEMORY_LABEL="$3" \
    bash "$HERE/watch-supervisor.sh" "shared-memory${3:+-$3}" \
    bash "$HERE/shared-memory-watch.sh" watch "$1" &
  pids+=($!); armed+=("$name ${1}s")
}
while read -r kind a b rest; do
  case "$kind" in
    SM) arm_sm "$a" "$b${rest:+ $rest}" "" ;;
    CHANNEL) arm_sm "$b" "$rest" "$a" ;;
    # A listed channel that is not armed stays visible in the watch itself, not only in --dry-run.
    SKIP) echo "NOTE: shared-memory [$a] not watched — $b${rest:+ $rest}" ;;
    CHANNEL_ERROR) echo "ERROR: shared-memory channels NOT watched — $a${b:+ $b}${rest:+ $rest} (fix $CHANNELS)" ;;
    REPO)
      REPO_ACTIVITY_STATE_DIR="$STATE" REPO_ACTIVITY_TAG="$a" GH_WATCH_REPOS="$rest" \
        GH_SELF_LOGIN="-" GH_ONLY_LOGINS="$(logins_for_tag "$a")" \
        bash "$HERE/watch-supervisor.sh" "repos-$a" \
        bash "$HERE/repo-activity-watch.sh" "$b" &
      pids+=($!); armed+=("$a [$rest] ${b}s") ;;
    SESSIONS)
      bash "$HERE/watch-supervisor.sh" parallel-sessions \
        bash "$HERE/parallel-sessions-watch.sh" "$INSTANCE" "$a" &
      pids+=($!); armed+=("parallel sessions ${a}s") ;;
  esac
done <<<"$PLAN"

echo "NOTE: collaboration watch armed, scope=$SCOPE ($SCOPE_LABEL) — $(IFS=';'; echo "${armed[*]}") (state: $STATE)"
if [[ "$ONLY_LOGINS" != "-" ]]; then
  echo "NOTE: reporting ONLY $ONLY_LOGINS (parties: $ONLY_PARTIES)${TOPICS:+ plus everything in topics: $TOPICS} — everything else, the operator's own other machines included, is dropped and NOT replayed after switching back"
fi

# The watch lives and dies with the session that armed it. A plain `wait` never returns
# (supervisors restart forever), so an orphaned tree would keep polling and keep the locks.
PARENT=$PPID
while kill -0 "$PARENT" 2>/dev/null; do sleep 5 & wait $!; done
exit 0
