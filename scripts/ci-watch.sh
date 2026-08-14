#!/usr/bin/env bash
# ci-watch.sh — wait for CI on a PR or a ref (branch OR tag) and report the verdict.
#
# WHY this exists (measured 2026-08-14, two broken ad-hoc watchers in one session):
#   1. `gh run list --branch <tag>` NEVER matches a tag run — the filter is a branch
#      filter. The ad-hoc loop compared an empty field against "completed" and spun
#      forever; silence looked exactly like "still running" (invariant P-1: a checker
#      that misses its target reports success — here, its cousin: it reports nothing).
#   2. zsh does not word-split unquoted variables: `set -- $pair` kept repo and ref
#      glued together and every gh call 404'd — swallowed by 2>/dev/null, surfaced
#      as a wrong rc that was then misread. Errors here are NEVER silenced.
# This script matches refs via the run's headBranch FIELD from JSON (works for tags
# and branches alike), enumerates every terminal state, and cannot end silently:
# exit 0 = all green · 1 = something failed/cancelled/timed out in CI · 2 = could
# not measure (no run appeared, bad repo, gh error, timeout) — 2 is loud on purpose,
# "unknown" must never be read as green.
#
# Usage:
#   scripts/ci-watch.sh pr  <owner/repo> <pr-number> [timeout_s]
#   scripts/ci-watch.sh ref <owner/repo> <ref>       [timeout_s]   # branch or tag
# Defaults: timeout 900 s, poll every 15 s (override: CI_WATCH_POLL). Needs gh.
set -u

MODE="${1:-}"; REPO="${2:-}"; TARGET="${3:-}"; TIMEOUT="${4:-900}"
POLL="${CI_WATCH_POLL:-15}"

usage() { echo "usage: ci-watch.sh pr|ref <owner/repo> <pr-number|ref> [timeout_s]" >&2; exit 2; }
[[ "$MODE" == "pr" || "$MODE" == "ref" ]] || usage
[[ -n "$REPO" && -n "$TARGET" ]] || usage

start=$(date +%s)
deadline=$(( start + TIMEOUT ))
warned_no_run=0

fail_unknown() { echo "CI-WATCH UNKNOWN: $*" >&2; exit 2; }

while :; do
  now=$(date +%s)
  if (( now >= deadline )); then
    fail_unknown "timeout after ${TIMEOUT}s — $MODE $REPO $TARGET never reached a terminal verdict (do NOT read this as green)"
  fi

  if [[ "$MODE" == "pr" ]]; then
    # Buckets are machine-readable: pass|fail|pending|skipping|cancel.
    json=$(gh pr checks "$TARGET" -R "$REPO" --json bucket 2>&1)
    rc=$?
    if (( rc != 0 )); then
      # gh exits 8 while checks are pending — that is a wait, not an error.
      if (( rc == 8 )) || grep -qi "pending" <<<"$json"; then sleep "$POLL"; continue; fi
      fail_unknown "gh pr checks failed (rc=$rc): $(head -c 200 <<<"$json")"
    fi
    counts=$(python3 -c '
import json, sys
b = [c.get("bucket") for c in json.load(sys.stdin)]
print(len(b), sum(x == "pending" for x in b), sum(x in ("fail", "cancel") for x in b))
' <<<"$json" 2>/dev/null) || fail_unknown "unparseable gh pr checks output"
    read -r total pending bad <<<"$counts"
    if (( total == 0 )); then fail_unknown "PR $TARGET reports zero checks — nothing measured"; fi
    if (( pending > 0 )); then sleep "$POLL"; continue; fi
    if (( bad > 0 )); then echo "CI-WATCH RED: $REPO PR #$TARGET — $bad failing/cancelled check(s)"; exit 1; fi
    echo "CI-WATCH GREEN: $REPO PR #$TARGET — $total checks, none failing"
    exit 0
  fi

  # ref mode: match the run's headBranch FIELD — tag runs land there too.
  json=$(gh run list -R "$REPO" --limit 30 --json headBranch,status,conclusion 2>&1) \
    || fail_unknown "gh run list failed: $(head -c 200 <<<"$json")"
  verdict=$(python3 -c '
import json, sys
ref = sys.argv[1]
runs = [r for r in json.load(sys.stdin) if r.get("headBranch") == ref]
if not runs:
    print("none - -")
else:
    r = runs[0]  # newest first
    print("found", r.get("status") or "-", r.get("conclusion") or "-")
' "$TARGET" <<<"$json" 2>/dev/null) || fail_unknown "unparseable gh run list output"
  read -r found status conclusion <<<"$verdict"

  if [[ "$found" == "none" ]]; then
    if (( warned_no_run == 0 )); then
      echo "ci-watch: no run for ref '$TARGET' yet (a just-pushed tag can take a moment) — waiting" >&2
      warned_no_run=1
    fi
    sleep "$POLL"; continue
  fi
  if [[ "$status" != "completed" ]]; then sleep "$POLL"; continue; fi
  case "$conclusion" in
    success)                    echo "CI-WATCH GREEN: $REPO $TARGET — success"; exit 0 ;;
    failure|cancelled|timed_out|startup_failure|action_required)
                                echo "CI-WATCH RED: $REPO $TARGET — $conclusion"; exit 1 ;;
    skipped|neutral)            echo "CI-WATCH GREEN: $REPO $TARGET — $conclusion (no failing verdict)"; exit 0 ;;
    *)                          fail_unknown "unmapped conclusion '$conclusion' — refusing to guess" ;;
  esac
done
