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

# Resolve the Python interpreter: the python.org installer on Windows ships ONLY
# `python`, and the Microsoft Store ships a `python3` STUB that resolves in PATH but
# does not run — so probe by RUNNING it, never with `command -v` (measured 2026-08-14:
# a colleague brain had no working `python3`, every reader below returned empty and
# brain-update.sh printed DONE without having done anything).
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python

MODE="${1:-}"; REPO="${2:-}"; TARGET="${3:-}"; TIMEOUT="${4:-900}"
POLL="${CI_WATCH_POLL:-15}"

usage() { echo "usage: ci-watch.sh pr|ref <owner/repo> <pr-number|ref> [timeout_s]" >&2; exit 2; }
[[ "$MODE" == "pr" || "$MODE" == "ref" ]] || usage
[[ -n "$REPO" && -n "$TARGET" ]] || usage

start=$(date +%s)
deadline=$(( start + TIMEOUT ))
warned_no_run=0

fail_unknown() { echo "CI-WATCH UNKNOWN: $*" >&2; exit 2; }

# A PR with a merge conflict gets NO pull_request run at all: GitHub cannot build the
# merge ref, so it creates nothing — no error, no message. "Zero checks" is therefore
# the same visible state as a dead CI, an exhausted quota or a workflow filter; one
# command separates them. Measured 2026-09-02: repo-outage and account-quota were both
# diagnosed AND published for a PR that simply read mergeable=CONFLICTING — while the
# mechanism sat documented in an instance memory since 08-13 and was not recalled.
# That is why this check lives in the TOOL: the verdict arrives with the diagnosis.
#
# ⚠ The field itself lies right after a push: GitHub recomputes mergeability lazily,
# and a read taken immediately after a rebase/force-push returns the OLD state
# (measured 2026-09-02, both directions: MERGEABLE right before a 405 conflict, and
# CONFLICTING right after the fixing force-push). One read is therefore not a
# measurement — the verdict requires TWO consecutive CONFLICTING reads a poll apart.
conflict_seen=0
warned_view_fail=0
pr_conflicting_check() {
  local m
  if ! m=$(gh pr view "$TARGET" -R "$REPO" --json mergeable --jq .mergeable 2>/dev/null); then
    # Fail-open by design (the deadline still ends the watch honestly), but not
    # silently — otherwise "gh broke" reads exactly like "no conflict".
    if (( warned_view_fail == 0 )); then
      echo "ci-watch: could not read mergeable for PR #$TARGET (gh error) — conflict check is flying blind this round" >&2
      warned_view_fail=1
    fi
    return 0
  fi
  if [[ "$m" == "CONFLICTING" ]]; then
    if (( conflict_seen )); then
      echo "CI-WATCH UNKNOWN: $REPO PR #$TARGET is CONFLICTING (two consecutive reads) — either GitHub creates no pull_request run for it at all (zero checks), or the checks you see are GREEN BUT STALE, computed before the base changed. Both mean the same thing: not mergeable, and no re-trigger helps — rebase the branch, then re-arm." >&2
      exit 2
    fi
    conflict_seen=1
    echo "ci-watch: PR #$TARGET reads CONFLICTING — re-checking next round (the field is stale right after a push)" >&2
  else
    conflict_seen=0
  fi
}

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
      # "no checks reported" right after a push is the SAME wait: the workflow run has
      # not been created yet. ref mode has always known this ("a just-pushed tag can take
      # a moment"); pr mode concluded UNKNOWN instead and exited, so a watch armed in the
      # same turn as the push reported no verdict at all — measured 2026-08-31, the run
      # existed seconds later. Waiting costs nothing: the deadline above still ends the
      # watch honestly if the checks genuinely never appear.
      if grep -qi "no checks reported" <<<"$json"; then
        pr_conflicting_check
        if (( warned_no_run == 0 )); then
          echo "ci-watch: no checks on PR #$TARGET yet (a just-pushed branch can take a" \
               "moment) — waiting" >&2
          warned_no_run=1
        fi
        sleep "$POLL"; continue
      fi
      fail_unknown "gh pr checks failed (rc=$rc): $(head -c 200 <<<"$json")"
    fi
    counts=$("$PY" -c '
import json, sys
b = [c.get("bucket") for c in json.load(sys.stdin)]
print(len(b), sum(x == "pending" for x in b), sum(x in ("fail", "cancel") for x in b))
' <<<"$json" 2>/dev/null) || fail_unknown "unparseable gh pr checks output"
    read -r total pending bad <<<"$counts"
    # Zero checks is the same ambiguity one level on: "this repo has no CI" and "the run
    # is not registered yet" arrive as the same empty list. Wait it out — if it is still
    # empty at the deadline, the timeout says so, and that IS the honest verdict.
    if (( total == 0 )); then
      pr_conflicting_check
      if (( warned_no_run == 0 )); then
        echo "ci-watch: PR #$TARGET reports zero checks yet — waiting" >&2
        warned_no_run=1
      fi
      sleep "$POLL"; continue
    fi
    if (( pending > 0 )); then sleep "$POLL"; continue; fi
    if (( bad > 0 )); then echo "CI-WATCH RED: $REPO PR #$TARGET — $bad failing/cancelled check(s)"; exit 1; fi
    # Green checks are NOT sufficient: a PR can carry all-green checks AND a conflict —
    # the checks then predate the base change and are never recomputed (measured
    # 2026-09-02 on a live PR: 7 SUCCESS checks, mergeable CONFLICTING, merge → 405).
    # GREEN here means "green AND mergeable"; a conflicting read loops for the
    # two-consecutive confirmation instead of exiting success.
    pr_conflicting_check
    if (( conflict_seen )); then sleep "$POLL"; continue; fi
    echo "CI-WATCH GREEN: $REPO PR #$TARGET — $total checks, none failing"
    exit 0
  fi

  # ref mode: match the run's headBranch FIELD — tag runs land there too.
  json=$(gh run list -R "$REPO" --limit 30 --json headBranch,status,conclusion 2>&1) \
    || fail_unknown "gh run list failed: $(head -c 200 <<<"$json")"
  verdict=$("$PY" -c '
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
