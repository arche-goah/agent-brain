#!/usr/bin/env bash
# watch-pr.sh — follow ONE pull request: one stdout line per new comment, inline review
# comment and review verdict; exits when the PR is merged or closed. For Monitor:
#
#   Monitor({ command: "bash core/scripts/watch-pr.sh <owner>/<repo> <nr> 60", timeout_ms: 1800000 })
#
# The repo-wide watch (scripts/collab-watch.sh) finds new PRs, merges and comments; it does
# NOT see a review verdict that carries no inline comment (GitHub has no repo-wide reviews
# endpoint). Following a specific PR through its review is this script's job.
#
# Requires gh (authenticated). Deliberately no standalone jq — `gh api --jq` carries its own,
# and a stock Windows workstation has gh without jq.
#
# Selftest: scripts/watch-pr.sh --selftest   (run by scripts/test-watch-pr.sh)
set -u

# The reviews endpoint has no `since` parameter, so the cutoff is applied client-side;
# `gh api --jq` takes no --arg, hence a placeholder substituted per poll.
Q_ISSUE='.[] | "COMMENT \(.user.login): \(.body | gsub("\n";" ") | .[0:250])"'
Q_CODE='.[] | "REVIEW-COMMENT \(.user.login) \(.path): \(.body | gsub("\n";" ") | .[0:250])"'
Q_REVIEW='.[] | select(.submitted_at > "__SINCE__") | "REVIEW \(.user.login) \(.state): \(.body | gsub("\n";" ") | .[0:250])"'

if [ "${1:-}" = "--selftest" ]; then
  rc=0
  # The one piece of logic this script owns: the cutoff must land in the filter and the
  # placeholder must not survive — a stale placeholder compares against the literal string
  # and replays every review on every poll.
  q=${Q_REVIEW/__SINCE__/2026-01-01T00:00:00Z}
  case "$q" in *__SINCE__*) echo "FAIL: placeholder not substituted"; rc=1 ;; esac
  case "$q" in *'"2026-01-01T00:00:00Z"'*) ;; *) echo "FAIL: timestamp missing from the filter"; rc=1 ;; esac
  if command -v jq >/dev/null 2>&1; then
    out=$(printf '%s' '[{"user":{"login":"x"},"body":"a\nb"}]' | jq -r "$Q_ISSUE")
    [ "$out" = "COMMENT x: a b" ] || { echo "FAIL issue filter: $out"; rc=1; }
    out=$(printf '%s' '[{"user":{"login":"y"},"state":"APPROVED","body":"ok","submitted_at":"2026-01-02T00:00:00Z"},
                        {"user":{"login":"z"},"state":"COMMENTED","body":"old","submitted_at":"2025-01-01T00:00:00Z"}]' \
          | jq -r "$q")
    [ "$out" = "REVIEW y APPROVED: ok" ] || { echo "FAIL review filter (negative control: the old review must stay out): $out"; rc=1; }
  else
    echo "SKIP: no standalone jq — filter syntax unchecked here (runtime uses gh --jq)"
  fi
  [ "$rc" = 0 ] && echo "selftest OK"
  exit "$rc"
fi

REPO="${1:-}"; PR="${2:-}"; INTERVAL="${3:-60}"
if [ -z "$REPO" ] || [ -z "$PR" ]; then
  echo "usage: watch-pr.sh <owner/repo> <pr-number> [interval-seconds]   |   --selftest" >&2
  exit 2
fi

last=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PARENT=$PPID
STEP="${WATCH_PR_STEP:-5}"

# --- one watch per PR on this machine (2026-10-26) --------------------------------------
# Several sessions on one machine and one account each followed the same PR — four calls per
# round per watch against the account's shared budget (the class of ci-watch.sh point 6). The
# first watch of a PR writes every line it prints into a stream file as well; a second call for
# the same PR FOLLOWS that file from the moment it attaches — no GitHub call of its own — and ends
# with the owner's MERGED/CLOSED line. A dead owner is taken over. Lock under $HOME (a session's
# TMPDIR can be private to it); WATCH_PR_LOCK_DIR overrides, WATCH_PR_SHARE=0 turns it off.
alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }
if [ "${WATCH_PR_SHARE:-1}" != 0 ]; then
  LOCKROOT="${WATCH_PR_LOCK_DIR:-$HOME/.cache/watch-pr}"
  L="$LOCKROOT/$(printf '%s|%s' "$REPO" "$PR" | cksum | tr -c '0-9\n' '-')"
  mkdir -p "$LOCKROOT" 2>/dev/null
  if ! mkdir "$L" 2>/dev/null; then
    owner=$(cat "$L/pid" 2>/dev/null)
    if alive "$owner"; then
      echo "NOTE: a watch for $REPO #$PR already runs on this machine (pid $owner) - following its lines instead of polling GitHub"
      off=$(wc -c < "$L/stream" 2>/dev/null | tr -d ' '); off=${off:-0}
      while alive "$owner"; do
        size=$(wc -c < "$L/stream" 2>/dev/null | tr -d ' '); size=${size:-0}
        if [ "$size" -gt "$off" ]; then
          new=$(tail -c +"$((off + 1))" "$L/stream" | head -c "$((size - off))")
          printf '%s\n' "$new"; off=$size
          case "$new" in *"PR #$PR MERGED"*|*"PR #$PR CLOSED"*) exit 0 ;; esac
        fi
        sleep "$STEP"
        alive "$PARENT" || exit 0
      done
      # the owner ended: its last lines, then stop if it saw the end — else take the watch over
      size=$(wc -c < "$L/stream" 2>/dev/null | tr -d ' '); size=${size:-0}
      if [ "$size" -gt "$off" ]; then
        new=$(tail -c +"$((off + 1))" "$L/stream"); printf '%s\n' "$new"
        case "$new" in *"PR #$PR MERGED"*|*"PR #$PR CLOSED"*) exit 0 ;; esac
      fi
    fi
    rm -rf "$L"
    mkdir "$L" 2>/dev/null || exec bash "$0" "$@"   # another call took it over first: follow that one
  fi
  echo $$ > "$L/pid"; : > "$L/stream"
  out() { tee -a "$L/stream"; }
else
  out() { cat; }
fi

echo "NOTE: watching $REPO #$PR (comments, reviews, merge/close), every ${INTERVAL}s"

while true; do
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # `|| true` on every call: a transient API failure must not end the watch silently.
  {
    gh api "repos/$REPO/issues/$PR/comments?since=$last" --jq "$Q_ISSUE" 2>/dev/null || true
    gh api "repos/$REPO/pulls/$PR/comments?since=$last" --jq "$Q_CODE"  2>/dev/null || true
    gh api "repos/$REPO/pulls/$PR/reviews" --jq "${Q_REVIEW/__SINCE__/$last}" 2>/dev/null || true
  } | out
  case "$(gh pr view "$PR" --repo "$REPO" --json state --jq .state 2>/dev/null || echo '')" in
    MERGED) echo "PR #$PR MERGED" | out; exit 0 ;;
    CLOSED) echo "PR #$PR CLOSED without merge" | out; exit 0 ;;
  esac
  last=$now
  for (( slept = 0; slept < INTERVAL; slept += STEP )); do
    sleep "$STEP"
    kill -0 "$PARENT" 2>/dev/null || exit 0
  done
done
