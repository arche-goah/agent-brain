#!/usr/bin/env bash
# Level 2 of the shared-memory awareness pair: poll for new commits WHILE a session is
# open and print ONE LINE PER FIND, then keep watching. Meant to be driven by the
# Monitor tool with persistent: true — the same shape as the PR org-watch, on purpose.
# Level 1 (helpers/shared-memory-check.sh, called from session-bootup) covers session
# boundaries; this one covers everything in between.
#
#   scripts/shared-memory-watch.sh watch [interval_s]   # default 300
#   scripts/shared-memory-watch.sh status
#   scripts/shared-memory-watch.sh disarm
#
# WHY IT DOES NOT EXIT ON A FIND (operator correction 2026-08-17): the first version
# exited after the first find. That turns every find into a re-arm ritual, and the
# window between exit and next arm is unwatched — while looking armed. It was also a
# DIFFERENT shape than the org-watch running beside it in the same session; two
# watchers, two mechanics, one of them depending on a human remembering something.
#
# THE MISSED-WINDOW PROPERTY DOES NOT DEPEND ON THE WATCHER RUNNING: the cursor lives
# in a FILE (shared with level 1) and advances only when a find is reported or when
# the commit was ours. Anything pushed while nothing watched is a find at the next
# poll, whenever that happens.
#
# OWN COMMITS ARE NOT AN EVENT (burned live 2026-08-17): the watch fired on its own
# session's push, consumed itself and was blind afterwards — armed-looking and dead.
# Filtering by author is the WRONG fix: one operator's name is identical on their Mac
# and their Windows workstation, so a name filter would also swallow the other own
# instance, which is exactly the signal we want. The identity-free discriminator: is
# the commit already reachable from this working copy? Ours are, foreign ones are not.
# No name, no email, no allowlist.
#
# Class behind it: a watchdog filter must be proven with a NEGATIVE CONTROL — an empty
# result looks the same whether nothing happened or the filter ate everything. That
# proof is scripts/shared-memory-watch-test.sh, and it is part of the deliverable.
set -uo pipefail

# Overridable so the watcher can run against a sandbox repo in the test. A find path
# nobody has ever SEEN fire is indistinguishable from a broken one.
REPO="${SHARED_MEMORY_REPO:-$HOME/Projects/brain-shared-memory}"
STATE_FILE="${SHARED_MEMORY_STATE:-${CLAUDE_PROJECT_DIR:-.}/config/shared-memory-state.json}"
LOCK_DIR="${SHARED_MEMORY_LOCK_DIR:-${CLAUDE_PROJECT_DIR:-.}/.claude-state}"
LOCK="$LOCK_DIR/shared-memory-watch.pid"
mkdir -p "$LOCK_DIR"

read_sha() {
  [[ -f "$STATE_FILE" ]] || return 1
  grep -o '"lastSeenSha" *: *"[^"]*"' "$STATE_FILE" 2>/dev/null | sed -E 's/.*"([^"]*)"$/\1/'
}

write_sha() {
  mkdir -p "$(dirname "$STATE_FILE")"
  printf '{\n  "lastSeenSha": "%s",\n  "lastCheckedAt": "%s"\n}\n' \
    "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_FILE"
}

lock_owner_alive() {
  [[ -f "$LOCK" ]] || return 1
  local pid
  pid=$(cat "$LOCK" 2>/dev/null)
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

case "${1:-status}" in
  status)
    if lock_owner_alive; then
      echo "armed: pid $(cat "$LOCK")"
    else
      echo "not armed"
    fi ;;

  disarm)
    rm -f "$LOCK"
    echo "disarmed" ;;

  watch|arm)   # `arm` kept as an alias so older callers and docs keep working
    # One machine can have several sessions open on the same brain. Only ONE should
    # poll — otherwise every session hammers the same fetch and all of them react to
    # the same commit. The lock is per machine, in gitignored state.
    # Claim and check in ONE step. `noclobber` makes the redirect fail if the file
    # already exists (O_EXCL), so there is no window between asking whether the lock is
    # free and taking it. The check-then-write version had one: two sessions arming
    # close together both passed the check and both wrote, and the file then named only
    # the last of them while both watchers polled.
    claim() { ( set -o noclobber; echo $$ > "$LOCK" ) 2>/dev/null; }
    if ! claim; then
      if lock_owner_alive; then
        echo "already armed by another session: pid $(cat "$LOCK") — skipping duplicate watcher"
        exit 0
      fi
      # The owner is gone without its trap having run (kill -9, crash, reboot). Clear
      # the corpse and claim once; a second failure is a real problem, not a stale lock.
      rm -f "$LOCK"
      claim || { echo "ERROR: cannot claim lock $LOCK"; exit 1; }
    fi
    # Only remove the lock if it STILL names this process. The unconditional `rm -f`
    # here deleted whatever lock happened to be there — including one a later session
    # had legitimately claimed after this one was presumed dead. The next session then
    # read "not armed" and started a second watcher on the same cursor, invisible to
    # `status`, which can only ever name one pid. Measured 2026-08-20: two watchers,
    # started six minutes apart, both polling.
    trap 'if [[ "$(cat "$LOCK" 2>/dev/null)" == "$$" ]]; then rm -f "$LOCK"; fi' EXIT
    [[ -d "$REPO/.git" ]] || { echo "ERROR: shared-memory repo not cloned: $REPO"; exit 1; }

    INTERVAL="${2:-300}"

    # A MISSING cursor used to be silent: the find condition required a non-empty
    # cursor, so with no state file the loop polled forever and reported nothing —
    # armed, green-looking, blind. Initialize loudly instead, and say what the
    # baseline became, so "older commits are not reported" is a stated fact.
    if ! read_sha >/dev/null 2>&1 || [[ -z "$(read_sha)" ]]; then
      git -C "$REPO" fetch -q origin main 2>/dev/null
      INIT=$(git -C "$REPO" rev-parse origin/main 2>/dev/null)
      if [[ -z "$INIT" ]]; then
        echo "ERROR: no cursor in $STATE_FILE and origin/main unreadable — refusing to watch blind"
        exit 1
      fi
      write_sha "$INIT"
      echo "NOTE: no cursor found — baseline set to ${INIT:0:8}; older commits are NOT reported"
    fi

    while true; do
      git -C "$REPO" fetch -q origin main 2>/dev/null
      REMOTE_HEAD=$(git -C "$REPO" rev-parse origin/main 2>/dev/null)
      LAST_SEEN=$(read_sha)

      if [[ -n "$REMOTE_HEAD" && -n "$LAST_SEEN" && "$REMOTE_HEAD" != "$LAST_SEEN" ]]; then
        if git -C "$REPO" merge-base --is-ancestor "$REMOTE_HEAD" HEAD 2>/dev/null; then
          write_sha "$REMOTE_HEAD"     # ours — advance silently, keep watching
        else
          COUNT=$(git -C "$REPO" rev-list --count "$LAST_SEEN..$REMOTE_HEAD" -- . 2>/dev/null)
          FILES=$(git -C "$REPO" diff --name-only "$LAST_SEEN" "$REMOTE_HEAD" -- . 2>/dev/null \
            | grep -v '^INDEX\.md$' | head -5 | tr '\n' '|' | sed 's/|/, /g; s/, $//')
          # The PARTY is the `von:` field of the changed entries, never the git account:
          # two of the three parties share one account, so `%an` cannot tell them apart
          # (measured 2026-08-22 — a session reported our own Windows machine as "the
          # colleague"). Falls back to a visibly unknown party rather than to a name.
          PARTIES=$(git -C "$REPO" diff --name-only "$LAST_SEEN" "$REMOTE_HEAD" -- . 2>/dev/null \
            | grep '\.md$' \
            | while read -r f; do
                git -C "$REPO" show "$REMOTE_HEAD:$f" 2>/dev/null \
                  | sed -n 's/^[[:space:]]*von:[[:space:]]*//p' | head -1
              done \
            | sort -u | tr '\n' '|' | sed 's/|/, /g; s/, $//')
          echo "FOUND: ${COUNT:-?} new commit(s) from ${PARTIES:-unknown party (no von: field)} — ${FILES:-see git log}"
          write_sha "$REMOTE_HEAD"     # cursor advances, watch CONTINUES
        fi
      fi

      sleep "$INTERVAL"
    done ;;

  *)
    echo "usage: $0 {watch [interval_s] | status | disarm}" >&2
    exit 64 ;;
esac
