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
#   3. (2026-10-12) GitHub can leave a check-run at status=in_progress with a conclusion
#      already set; `gh pr checks` buckets it as pending forever. pr mode therefore
#      reads the head commit's check-runs and counts a check-run by its conclusion.
# This script matches refs via the run's headBranch FIELD from JSON (works for tags
# and branches alike), enumerates every terminal state, and cannot end silently:
# exit 0 = all green · 1 = something failed/cancelled/timed out in CI · 2 = could
# not measure (no run appeared, bad repo, gh error, timeout) — 2 is loud on purpose,
# "unknown" must never be read as green · 3 = the repo has no Actions workflow at all,
# so there is nothing to wait for — also NOT green: whoever merges on it says so.
#
# Usage:
#   scripts/ci-watch.sh pr  <owner/repo> <pr-number> [timeout_s]
#   scripts/ci-watch.sh ref <owner/repo> <ref>       [timeout_s]   # branch or tag
# Defaults: timeout 1800 s, poll every 15 s (override: CI_WATCH_POLL). Needs gh.
# The default must outlast the slowest job of the core's own CI: measured 2026-10-12,
# `portability (windows-latest)` ran 13m41s and 14m26s, plus queue time — the old 900 s
# ended a watch on a run that turned green minutes later (UNKNOWN, honest but useless).
set -u

# Resolve the Python interpreter: the python.org installer on Windows ships ONLY
# `python`, and the Microsoft Store ships a `python3` STUB that resolves in PATH but
# does not run — so probe by RUNNING it, never with `command -v` (measured 2026-08-14:
# a colleague brain had no working `python3`, every reader below returned empty and
# brain-update.sh printed DONE without having done anything).
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python

MODE="${1:-}"; REPO="${2:-}"; TARGET="${3:-}"; TIMEOUT="${4:-1800}"
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

# "No checks / no run" is also what a repo WITHOUT any workflow shows, forever — the watch
# then waited its whole timeout (measured 2026-10-11: 900 s on a private repo with no
# .github/workflows, while a merge guard demanded the watch). Asked once, on the first empty
# round: zero workflows ends the watch at once with its own verdict. Any other answer
# (a count, an error, an unreadable reply) keeps waiting — only an explicit 0 is proof.
noci_probed=0
no_ci_check() {
  (( noci_probed )) && return 0
  (( conflict_seen )) && return 0       # a pending conflict verdict goes first
  noci_probed=1
  local n
  n=$(gh api "repos/$REPO/actions/workflows" --jq .total_count 2>/dev/null) || return 0
  if [[ "$n" == "0" ]]; then
    echo "CI-WATCH NO-CI: $REPO has no Actions workflow — nothing to wait for (not green)"
    exit 3
  fi
}

# A check-run can be FINISHED while its status still says in_progress: measured 2026-10-12
# on a suite PR, check-run `release-preflight` read status=in_progress, conclusion=success,
# completed_at set — the workflow run was completed/success, GitHub never flipped the
# check-run's status. `gh pr checks` derives its bucket from the status and reported
# `pending` for good; the watch waited out its whole timeout and ended UNKNOWN on an
# all-green PR, and no timeout reaches a check that never flips. The conclusion is the
# fact: a check-run with a non-null conclusion is finished whatever its status says. So
# while `pr checks` reports pending entries, the head commit's check-runs are read and
# every pending entry that names a check-run WITH a conclusion is recounted by that
# conclusion; a pending entry without a check-run (a commit status) or whose check-run
# has no conclusion yet keeps its bucket. Any unreadable answer on the way leaves the
# counts as they were — the fallback is to keep waiting, never to turn green.
warned_stale=0
stale_checkrun_recount() {   # reads $json, may lower $pending and raise $bad
  local sha cr recount stale
  sha=$(gh pr view "$TARGET" -R "$REPO" --json headRefOid --jq .headRefOid 2>/dev/null) || return 0
  [[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || return 0
  cr=$(gh api "repos/$REPO/commits/$sha/check-runs?per_page=100" \
         --jq '[.check_runs[] | {name: .name, conclusion: .conclusion}]' 2>/dev/null) || return 0
  recount=$("$PY" -c '
import json, sys
checks = json.load(sys.stdin)
try:
    runs = {r.get("name"): r.get("conclusion") for r in json.loads(sys.argv[1])}
except Exception:
    runs = {}
pending = bad = stale = 0
for c in checks:
    b = c.get("bucket")
    if b in ("fail", "cancel"):
        bad += 1
    elif b == "pending":
        concl = runs.get(c.get("name"))
        if concl is None:
            pending += 1          # no check-run, or one that is genuinely still running
        else:
            stale += 1
            if concl not in ("success", "skipped", "neutral"):
                bad += 1
print(pending, bad, stale)
' "$cr" <<<"$json" 2>/dev/null) || return 0
  read -r pending bad stale <<<"$recount"
  if (( stale > 0 && warned_stale == 0 )); then
    echo "ci-watch: $stale check-run(s) on PR #$TARGET carry a conclusion while their status" \
         "still says in_progress (GitHub left the status stale) — counting them by conclusion" >&2
    warned_stale=1
  fi
}

while :; do
  now=$(date +%s)
  if (( now >= deadline )); then
    fail_unknown "timeout after ${TIMEOUT}s — $MODE $REPO $TARGET never reached a terminal verdict (do NOT read this as green)"
  fi

  if [[ "$MODE" == "pr" ]]; then
    # Buckets are machine-readable: pass|fail|pending|skipping|cancel. The name is
    # carried along so a pending entry can be matched to its check-run (below).
    json=$(gh pr checks "$TARGET" -R "$REPO" --json bucket,name 2>&1)
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
        no_ci_check
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
      no_ci_check
      if (( warned_no_run == 0 )); then
        echo "ci-watch: PR #$TARGET reports zero checks yet — waiting" >&2
        warned_no_run=1
      fi
      sleep "$POLL"; continue
    fi
    if (( pending > 0 )); then stale_checkrun_recount; fi
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

  # ref mode: the verdict belongs to the commit the ref points at NOW, across EVERY
  # workflow that ran on it. Until 2026-10-05 this took runs[0] — the newest run of ANY
  # workflow on the branch: measured, a one-minute "dynamic" run on main reported success
  # while the five-minute CI run of the same push was still going and then went red, and
  # a run of an OLDER commit counted for a newer tip. Both read as "main is green".
  # The commits endpoint resolves a branch AND a tag (peeled) to its commit.
  sha=$(gh api "repos/$REPO/commits/$TARGET" --jq .sha 2>/dev/null)
  if [[ -z "$sha" ]]; then
    if (( warned_no_run == 0 )); then
      echo "ci-watch: ref '$TARGET' not resolvable on $REPO yet — waiting" >&2
      warned_no_run=1
    fi
    sleep "$POLL"; continue
  fi
  json=$(gh run list -R "$REPO" --limit 50 --json headBranch,headSha,status,conclusion,name 2>&1) \
    || fail_unknown "gh run list failed: $(head -c 200 <<<"$json")"
  verdict=$("$PY" -c '
import json, sys
ref, sha = sys.argv[1], sys.argv[2]
# A bare commit sha is no branch name: matching headBranch == ref never hit, and the watch
# waited out its timeout (measured 2026-10-09). A ref that IS the resolved commit matches by sha.
bare = len(ref) >= 7 and all(c in "0123456789abcdef" for c in ref.lower()) and sha.startswith(ref.lower())
runs = [r for r in json.load(sys.stdin)
        if r.get("headSha") == sha and (bare or r.get("headBranch") == ref)]
if not runs:
    print("none - -")
elif any(r.get("status") != "completed" for r in runs):
    print("found in_progress -")
else:
    bad = [r.get("conclusion") for r in runs
           if r.get("conclusion") not in ("success", "skipped", "neutral")]
    print("found completed", bad[0] if bad else "success")
' "$TARGET" "$sha" <<<"$json" 2>/dev/null) || fail_unknown "unparseable gh run list output"
  read -r found status conclusion <<<"$verdict"

  if [[ "$found" == "none" ]]; then
    no_ci_check
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
