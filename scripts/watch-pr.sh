#!/usr/bin/env bash
# watch-pr.sh — follow ONE pull request: one stdout line per new comment, inline review
# comment and review verdict; exits when the PR is merged or closed. For Monitor:
#
#   Monitor({ command: "bash core/scripts/watch-pr.sh <owner>/<repo> <nr> 60", persistent: true })
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
echo "NOTE: watching $REPO #$PR (comments, reviews, merge/close), every ${INTERVAL}s"

while true; do
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # `|| true` on every call: a transient API failure must not end the watch silently.
  gh api "repos/$REPO/issues/$PR/comments?since=$last" --jq "$Q_ISSUE" 2>/dev/null || true
  gh api "repos/$REPO/pulls/$PR/comments?since=$last" --jq "$Q_CODE"  2>/dev/null || true
  gh api "repos/$REPO/pulls/$PR/reviews" --jq "${Q_REVIEW/__SINCE__/$last}" 2>/dev/null || true
  case "$(gh pr view "$PR" --repo "$REPO" --json state --jq .state 2>/dev/null || echo '')" in
    MERGED) echo "PR #$PR MERGED"; exit 0 ;;
    CLOSED) echo "PR #$PR CLOSED without merge"; exit 0 ;;
  esac
  last=$now
  for (( slept = 0; slept < INTERVAL; slept += 5 )); do
    sleep 5
    kill -0 "$PARENT" 2>/dev/null || exit 0
  done
done
