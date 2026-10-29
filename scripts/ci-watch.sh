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
#   4. (2026-10-14) A branch ref MOVES while it is watched: eight merges to main in 35
#      minutes, one watch per merge; every CI run but the last was cancelled by its
#      successor, the watches followed the tip and ran out their 1800 s while the newest
#      run was still going — two ended UNKNOWN after 30 min, none said why. ref mode now
#      names a move, restarts its clock for the new commit (at most CI_WATCH_MOVES_MAX
#      moves, default 5, then UNKNOWN names the churn), reads a `cancelled` conclusion as
#      RED only while the ref still points at that commit (a cancelled run of a commit the
#      ref has left is superseded, not a verdict), and lists the runs of the commit itself
#      (`actions/runs?head_sha=`) instead of the newest 50 runs of the repo, which a busy
#      day pushed the watched commit out of.
#   5. (2026-10-19) Three sessions on one machine, one GitHub account: `gh pr checks`
#      answered "API rate limit already exceeded for user ID …" while `gh api rate_limit`
#      still showed thousands of requests free (GitHub's secondary limit). The watch
#      printed UNKNOWN and exited at once — blind from then on, with CI still running.
#      Every gh call now goes through `ghq`: a rate-limit answer (primary or secondary,
#      HTTP 403/429 with rate-limit wording) prints ONE `CI-WATCH BLOCKED` line per block,
#      waits (until the reset `gh api rate_limit` names for an exhausted resource, else
#      exponential backoff 60 s → 15 min with jitter) and resumes polling. The blocked
#      time EXTENDS the verdict deadline. A block longer than CI_WATCH_RL_CEILING
#      (default 7200 s: a primary window resets hourly, so two hours of block is not
#      weather) ends as UNKNOWN naming the duration.
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
#   CI_WATCH_SHA=<pushed sha> scripts/ci-watch.sh pr …   # after a push: wait for THAT head
#   CI_WATCH_WAIT_ALL=1 scripts/ci-watch.sh pr …         # pr: no early red, wait for every check
#   A second call for the same target on this machine attaches to the first (point 6).
# Defaults: timeout 3600 s, poll every 15 s (override: CI_WATCH_POLL). Needs gh.
# The default must outlast the slowest job of the core's own CI: measured 2026-10-12,
# `portability (windows-latest)` ran 13m41s and 14m26s, plus queue time — the old 900 s
# ended a watch on a run that turned green minutes later (UNKNOWN, honest but useless).
# Raised 1800 -> 3600 s on 2026-10-26: since the CI runs every fixture suite on three systems a
# run takes about 36 min (Windows-bound); three watches after three merges that day all ended
# UNKNOWN at 1800 s on runs that were green. Start it with Bash run_in_background, NOT Monitor:
# the harness kills a Monitor after 30 min at most, so a Monitor watch cannot outlast such a run.
set -u

# Resolve the Python interpreter: the python.org installer on Windows ships ONLY
# `python`, and the Microsoft Store ships a `python3` STUB that resolves in PATH but
# does not run — so probe by RUNNING it, never with `command -v` (measured 2026-08-14:
# a colleague brain had no working `python3`, every reader below returned empty and
# brain-update.sh printed DONE without having done anything).
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python

MODE="${1:-}"; REPO="${2:-}"; TARGET="${3:-}"; TIMEOUT="${4:-3600}"
POLL="${CI_WATCH_POLL:-15}"

usage() { echo "usage: ci-watch.sh pr|ref <owner/repo> <pr-number|ref> [timeout_s]" >&2; exit 2; }
[[ "$MODE" == "pr" || "$MODE" == "ref" ]] || usage
[[ -n "$REPO" && -n "$TARGET" ]] || usage
# The form is checked here, not by the first gh call (2026-10-27: `pr 33 --repo x` took 33 as the
# repo and `--repo` as the PR and died later on an unbound variable instead of naming the usage).
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "ci-watch: '$REPO' is not <owner/repo>" >&2; usage; }
[[ "$MODE" != "pr" || "$TARGET" =~ ^[0-9]+$ ]] || { echo "ci-watch: '$TARGET' is not a PR number" >&2; usage; }
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || { echo "ci-watch: timeout '$TIMEOUT' is not a number of seconds" >&2; usage; }

# --- one watch per target on this machine (point 6, 2026-10-26) ---------------------------
# Several sessions and agents on one machine and one GitHub account each armed their own watch
# on the same PR or ref (2026-10-19: three duplicate main watchers, up to ~15 ci-watch at once —
# the account's secondary rate limit). Point 5 waits a block out; this keeps the block from
# coming: a second call with the same mode, repo, target and CI_WATCH_SHA ATTACHES to the
# running watch — it reads the owner's result file, never GitHub, and ends with the owner's
# lines and exit code. A dead owner leaves its directory behind; the next call takes it over.
# The lock lives under $HOME (a session's TMPDIR can be private to it). CI_WATCH_SHARE=0 = off.
if [[ -z "${CI_WATCH_SHARED_CHILD:-}" && "${CI_WATCH_SHARE:-1}" != 0 ]]; then
  LOCKROOT="${CI_WATCH_LOCK_DIR:-$HOME/.cache/ci-watch}"
  L="$LOCKROOT/$(printf '%s|%s|%s|%s' "$MODE" "$REPO" "$TARGET" "${CI_WATCH_SHA:-}" | cksum | tr -c '0-9\n' '-')"
  mkdir -p "$LOCKROOT" 2>/dev/null
  alive() { [[ -n "$1" ]] && kill -0 "$1" 2>/dev/null; }
  replay() { cat "$L/out" 2>/dev/null; cat "$L/err" >&2 2>/dev/null; exit "$(cat "$L/rc")"; }
  if ! mkdir "$L" 2>/dev/null; then
    owner=$(cat "$L/pid" 2>/dev/null)
    if alive "$owner"; then
      echo "CI-WATCH SHARED: a watch for $REPO $MODE $TARGET already runs on this machine (pid $owner) — waiting for its verdict instead of polling GitHub"
      while alive "$owner" && [[ ! -f "$L/rc" ]]; do sleep "$POLL"; done
      [[ -f "$L/rc" ]] && replay
    fi
    rm -rf "$L"
    mkdir "$L" 2>/dev/null || exec bash "$0" "$@"   # another call took it over first: attach to that one
  fi
  echo $$ > "$L/pid"
  { CI_WATCH_SHARED_CHILD=1 bash "$0" "$@" 2>"$L/err"; echo $? > "$L/rc.tmp"; } | tee "$L/out"
  cat "$L/err" >&2
  mv "$L/rc.tmp" "$L/rc"
  exit "$(cat "$L/rc")"
fi

start=$(date +%s)
deadline=$(( start + TIMEOUT ))
warned_no_run=0
# An unparseable gh reply is a transient of the run being registered (measured 2026-10-10:
# 'no checks yet' on one poll, unparseable on the next, 11 green checks a round later).
# One or two such polls are a wait; three in a row are a verdict (UNKNOWN).
unparsed=0
UNPARSED_MAX=${CI_WATCH_UNPARSED_MAX:-3}
gh_fail=0
# ref mode: the commit the ref pointed at on the previous poll, and how often it moved.
last_sha=""
moves=0
MOVES_MAX=${CI_WATCH_MOVES_MAX:-5}

fail_unknown() { echo "CI-WATCH UNKNOWN: $*" >&2; exit 2; }

# --- rate limit (header, point 5) ----------------------------------------------------
# ghq <gh args…> runs gh in THIS shell (never inside $(…), so the deadline extension
# survives) and sets gh_out (stdout), gh_err (stderr), gh_rc. A rate-limit answer is
# never returned to the caller: ghq waits it out and asks again.
RL_BASE=${CI_WATCH_RL_BACKOFF:-60}       # first secondary backoff, seconds
RL_MAX=${CI_WATCH_RL_BACKOFF_MAX:-900}   # backoff cap
RL_CEILING=${CI_WATCH_RL_CEILING:-7200}  # a block longer than this is a verdict (UNKNOWN)
RL_MARGIN=${CI_WATCH_RL_MARGIN:-5}       # slack after a primary reset
RL_RE='rate limit|abuse detection|HTTP 429|too many requests'
rl_since=0; rl_step=0
GH_ERR=$(mktemp "${TMPDIR:-/tmp}/ci-watch-err.XXXXXX") || fail_unknown "mktemp failed"
trap 'rm -f "$GH_ERR"' EXIT
gh_out=""; gh_err=""; gh_rc=0

fmt_time() { date -d "@$1" '+%H:%M:%S %Z' 2>/dev/null || date -r "$1" '+%H:%M:%S %Z' 2>/dev/null || echo "epoch $1"; }

rl_wait() {
  local now wait reset how
  now=$(date +%s)
  if (( rl_since > 0 && now - rl_since >= RL_CEILING )); then
    fail_unknown "rate-limited for $(( now - rl_since ))s on $REPO $TARGET (ceiling ${RL_CEILING}s) — no CI verdict was read (do NOT read as green)"
  fi
  # An exhausted primary resource names its own reset; anything else is the secondary limit.
  reset=$(gh api rate_limit --jq '[.resources.core, .resources.graphql] | map(select(.remaining == 0) | .reset) | max // empty' 2>/dev/null)
  if [[ "$reset" =~ ^[0-9]+$ ]]; then
    wait=$(( reset > now ? reset - now : 0 )); wait=$(( wait + RL_MARGIN )); how="primary limit exhausted, reset"
  else
    wait=$(( RL_BASE << rl_step ))
    (( wait < RL_MAX )) && rl_step=$(( rl_step + 1 ))
    (( wait > 0 )) && wait=$(( wait + RANDOM % (wait / 4 + 1) ))
    (( wait > RL_MAX )) && wait=$RL_MAX
    how="secondary limit, backoff"
  fi
  local start_b=$rl_since left
  (( start_b == 0 )) && start_b=$now
  left=$(( start_b + RL_CEILING - now ))   # never sleep past the ceiling
  (( left < 0 )) && left=0
  (( wait > left )) && wait=$left
  if (( rl_since == 0 )); then
    rl_since=$now
    echo "CI-WATCH BLOCKED: GitHub API rate limit — waiting until $(fmt_time $(( now + wait ))) (${wait}s, $how; blocked time extends the deadline)"
  else
    echo "ci-watch: still rate-limited after $(( now - rl_since ))s — next try in ${wait}s ($how)" >&2
  fi
  sleep "$wait"
  deadline=$(( deadline + wait ))
}

# A transport failure is weather, not a verdict (2026-10-27: `pr 157` ended UNKNOWN on one
# "TLS handshake timeout" while its CI kept running). ghq retries it a poll later, up to
# CI_WATCH_NET_MAX in a row (default 5); the waited time extends the deadline like a block.
NET_RE='TLS handshake timeout|i/o timeout|connection reset|connection refused|unexpected EOF|no such host|context deadline exceeded|HTTP 50[234]'
NET_MAX=${CI_WATCH_NET_MAX:-5}
net_fails=0
ghq() {
  while :; do
    gh_out=$(gh "$@" 2>"$GH_ERR"); gh_rc=$?
    gh_err=$(cat "$GH_ERR" 2>/dev/null)
    if (( gh_rc != 0 )) && grep -qiE "$RL_RE" <<<"$gh_out$gh_err"; then rl_wait; continue; fi
    if (( gh_rc != 0 )) && grep -qiE "$NET_RE" <<<"$gh_err" && (( net_fails < NET_MAX )); then
      net_fails=$(( net_fails + 1 ))
      echo "ci-watch: network error ($(grep -oiE "$NET_RE" <<<"$gh_err" | head -1)), try $net_fails of $NET_MAX — again in ${POLL}s" >&2
      sleep "$POLL"; deadline=$(( deadline + POLL )); continue
    fi
    (( gh_rc == 0 )) && net_fails=0
    if (( rl_since > 0 )); then
      echo "ci-watch: rate-limit block over after $(( $(date +%s) - rl_since ))s — polling resumed" >&2
      rl_since=0; rl_step=0
    fi
    return "$gh_rc"
  done
}

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
  ghq pr view "$TARGET" -R "$REPO" --json mergeable --jq .mergeable; m=$gh_out
  if (( gh_rc != 0 )); then
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
  ghq api "repos/$REPO/actions/workflows" --jq .total_count || return 0
  n=$gh_out
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
# Green checks are only the jobs GitHub has LISTED so far. A workflow run that has started
# but not yet created its jobs contributes no check at all — measured 2026-10-16 on a core
# PR: the fast CodeQL run finished with 4 green checks while the main workflow run (created
# 52 s before the verdict, status in_progress, ten jobs queued) had no check listed yet;
# the watch said GREEN. So before GREEN, the head commit's workflow RUNS are read: any run
# that is not completed means no verdict yet. An unreadable answer keeps the old behaviour
# (the listed checks decide) — the deadline still bounds every wait.
# A watch armed right after a push reads the PREVIOUS head: for some seconds GitHub still
# reports the old headRefOid and the old commit's checks. Measured 2026-10-16 on a core PR:
# a merge of main into the branch was pushed, the watch was armed in the same turn and said
# `GREEN — 14 checks` within a minute, all 14 of them the old head's; the new head's runs
# were all pending. CI_WATCH_SHA=<the pushed commit> (full or short) closes it: until the
# PR's head is that commit, nothing counts. Without it the behaviour is unchanged.
EXPECTED_SHA="${CI_WATCH_SHA:-}"
warned_expected=0
pr_head_not_yet_expected() {   # exit 0 = the PR does not show the expected head yet
  [[ -n "$EXPECTED_SHA" ]] || return 1
  local head
  ghq pr view "$TARGET" -R "$REPO" --json headRefOid --jq .headRefOid || return 0
  head=$gh_out
  [[ "$head" == "$EXPECTED_SHA"* ]] && return 1
  if (( warned_expected == 0 )); then
    echo "ci-watch: PR #$TARGET still shows head ${head:0:7}, waiting for ${EXPECTED_SHA:0:7}" >&2
    warned_expected=1
  fi
  return 0
}

# The same race without CI_WATCH_SHA, second incident (2026-10-19, a core PR): armed right after
# a push, the watch said `RED — 4 failing/cancelled` — the PREVIOUS run's checks; a minute later
# the new head stood on pending. The pushed commit is visible at once on the branch ref (a push
# writes it), while the PR's headRefOid follows asynchronously — so before ANY verdict, green or
# red, the PR head is compared with its branch tip: different = the PR has not caught up, the
# checks it lists belong to an older commit, wait. One extra read per verdict, none per poll.
# An unreadable answer (gh error, a deleted head branch after a merge, an old stub) does not
# block: the behaviour is then the one before this check, and the deadline still bounds it.
warned_behind=0
pr_head_behind_branch() {   # exit 0 = the PR's head is not yet its branch tip
  local head branch repo tip
  ghq pr view "$TARGET" -R "$REPO" --json headRefOid,headRefName,headRepository,headRepositoryOwner \
      --jq '[.headRefOid, .headRefName, .headRepositoryOwner.login + "/" + .headRepository.name] | @tsv' || return 1
  IFS=$'\t' read -r head branch repo <<<"$gh_out"
  [[ "$head" =~ ^[0-9a-f]{40}$ && -n "$branch" && "$repo" == */?* ]] || return 1
  ghq api "repos/$repo/git/ref/heads/$branch" --jq .object.sha || return 1
  tip=$gh_out
  [[ "$tip" =~ ^[0-9a-f]{40}$ ]] || return 1
  [[ "$tip" == "$head" ]] && return 1
  if (( warned_behind == 0 )); then
    echo "ci-watch: PR #$TARGET still shows head ${head:0:7}, its branch is already at ${tip:0:7}" \
         "(a push the PR has not caught up with) — its listed checks are the old head's; waiting" >&2
    warned_behind=1
  fi
  return 0
}

warned_open_run=0
pr_run_still_open() {   # exit 0 = a run of the head commit is still open
  local sha open
  ghq pr view "$TARGET" -R "$REPO" --json headRefOid --jq .headRefOid || return 1
  sha=$gh_out
  [[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || return 1
  ghq api "repos/$REPO/actions/runs?head_sha=$sha&per_page=100" \
      --jq '[.workflow_runs[] | select(.status != "completed")] | length' || return 1
  open=$gh_out
  [[ "$open" =~ ^[0-9]+$ ]] || return 1
  (( open > 0 )) || return 1
  if (( warned_open_run == 0 )); then
    echo "ci-watch: listed checks on PR #$TARGET are green, but $open workflow run(s) of the" \
         "head commit are still open (jobs not listed yet) — waiting" >&2
    warned_open_run=1
  fi
  return 0
}

warned_stale=0
stale_checkrun_recount() {   # reads $json, may lower $pending and raise $bad
  local sha cr recount stale
  ghq pr view "$TARGET" -R "$REPO" --json headRefOid --jq .headRefOid || return 0
  sha=$gh_out
  [[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || return 0
  ghq api "repos/$REPO/commits/$sha/check-runs?per_page=100" \
      --jq '[.check_runs[] | {name: .name, conclusion: .conclusion}]' || return 0
  cr=$gh_out
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

# The head check above compares the PR's head with its branch tip. Both can already name the
# pushed commit while `pr checks` still lists the PREVIOUS commit's checks: measured 2026-10-25
# on a suite PR — a watch armed right after a fix push said `RED — 2 failing/cancelled`, the
# old head's two red jobs; the pushed head never had any run but one green one. So before a
# red verdict the head commit's own check-runs are read: the red stands when one of them
# failed, or when a listed failing check has no check-run there at all (a commit status).
# None yet, or the listed failing ones still running/green on the head = the old run's red,
# wait. Unreadable = the behaviour before this check; the deadline still bounds the wait.
warned_oldred=0
pr_red_not_of_head() {   # exit 0 = the listed red belongs to an older commit than the head
  local sha cr verdict
  ghq pr view "$TARGET" -R "$REPO" --json headRefOid --jq .headRefOid || return 1
  sha=$gh_out
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || return 1
  ghq api "repos/$REPO/commits/$sha/check-runs?per_page=100" \
      --jq '[.check_runs[] | {name: .name, conclusion: .conclusion}]' || return 1
  cr=$gh_out
  verdict=$("$PY" -c '
import json, sys
listed = json.load(sys.stdin)
runs = {r.get("name"): r.get("conclusion") for r in json.loads(sys.argv[1])}
BAD = {"failure", "cancelled", "timed_out", "action_required", "startup_failure"}
failing = [c.get("name") for c in listed if c.get("bucket") in ("fail", "cancel")]
real = any(v in BAD for v in runs.values()) or (runs and any(n not in runs for n in failing))
print("real" if real else "old")
' "$cr" <<<"$json" 2>/dev/null) || return 1
  [[ "$verdict" == old ]] || return 1
  if (( warned_oldred == 0 )); then
    echo "ci-watch: PR #$TARGET lists failing checks, but none of them failed on the head" \
         "commit ${sha:0:7} (its runs are new or still going) — the old run's red; waiting" >&2
    warned_oldred=1
  fi
  return 0
}

while :; do
  now=$(date +%s)
  if (( now >= deadline )); then
    fail_unknown "timeout after ${TIMEOUT}s — $MODE $REPO $TARGET never reached a terminal verdict (do NOT read this as green)"
  fi

  if [[ "$MODE" == "pr" ]]; then
    if pr_head_not_yet_expected; then sleep "$POLL"; continue; fi
    # Buckets are machine-readable: pass|fail|pending|skipping|cancel. The name is
    # carried along so a pending entry can be matched to its check-run (below).
    ghq pr checks "$TARGET" -R "$REPO" --json bucket,name
    rc=$gh_rc; json=$gh_out
    if (( rc != 0 )); then
      json="$gh_out$gh_err"
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
    # A `cancel` entry whose check name ALSO appears with another bucket is a superseded run
    # (two runs on one commit, the concurrency group cancelled the older): measured 2026-10-26
    # on a core PR, the watch reported "4 failing/cancelled check(s)" with exit 1 while the
    # surviving run was still going and turned green. Only a cancel without a sibling counts.
    if ! counts=$("$PY" -c '
import json, sys
cs = json.load(sys.stdin)
live = {c.get("name") for c in cs if c.get("bucket") != "cancel"}
b = [c.get("bucket") for c in cs if not (c.get("bucket") == "cancel" and c.get("name") in live)]
print(len(b), sum(x == "pending" for x in b), sum(x in ("fail", "cancel") for x in b), sum(x == "fail" for x in b))
' <<<"$json" 2>/dev/null); then
      unparsed=$((unparsed + 1))
      if (( unparsed >= UNPARSED_MAX )); then
        fail_unknown "unparseable gh pr checks output on $unparsed polls in a row: $(head -c 200 <<<"$json")"
      fi
      echo "ci-watch: gh pr checks output not parseable yet (poll $unparsed of $UNPARSED_MAX) — waiting" >&2
      sleep "$POLL"; continue
    fi
    unparsed=0
    read -r total pending bad failed <<<"$counts"
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
    # A FAILED check does not turn green while the others finish: report it at once. Measured
    # 2026-10-21 on a core PR: lint red after 6 min, one Windows job still running 18 min later,
    # the watch silent the whole time and the red unseen. Only `fail` counts here — a `cancel`
    # can be a superseded run and still waits for the full picture; the head check guards the
    # old-run race as for every verdict.
    # CI_WATCH_WAIT_ALL=1 waits for every check before the verdict and names the failing ones (2026-10-29,
    # measured on the macOS instance: one check red on every PR for a runner image change - each watch ended
    # at once, and twice "only that check is red" was read while the other jobs still ran; one of them was
    # really red). Without the variable the early report above stays the default.
    if (( pending > 0 && ${failed:-0} > 0 )) && [[ "${CI_WATCH_WAIT_ALL:-}" != 1 ]] && ! pr_head_behind_branch && ! pr_red_not_of_head; then
      echo "CI-WATCH RED: $REPO PR #$TARGET — $failed failing check(s), $pending still running (a failed check does not turn green)"
      exit 1
    fi
    if (( pending > 0 )); then sleep "$POLL"; continue; fi
    if pr_head_behind_branch; then sleep "$POLL"; continue; fi
    if (( bad > 0 )) && pr_red_not_of_head; then sleep "$POLL"; continue; fi
    if (( bad > 0 )); then
      names=$("$PY" -c 'import json,sys; print(", ".join(sorted({c.get("name","?") for c in json.load(sys.stdin) if c.get("bucket") in ("fail","cancel")})))' <<<"$json" 2>/dev/null)
      echo "CI-WATCH RED: $REPO PR #$TARGET — $bad failing/cancelled check(s)${names:+: $names}"; exit 1
    fi
    # Green checks are NOT sufficient: a PR can carry all-green checks AND a conflict —
    # the checks then predate the base change and are never recomputed (measured
    # 2026-09-02 on a live PR: 7 SUCCESS checks, mergeable CONFLICTING, merge → 405).
    # GREEN here means "green AND mergeable"; a conflicting read loops for the
    # two-consecutive confirmation instead of exiting success.
    pr_conflicting_check
    if (( conflict_seen )); then sleep "$POLL"; continue; fi
    if pr_run_still_open; then sleep "$POLL"; continue; fi
    # Green needs the SAME head on two polls. Measured 2026-10-28 on a core PR: a watch armed
    # right after `gh pr update-branch` said `GREEN — 14 checks` on its first poll — the PR head
    # AND its branch tip still named the old commit (the merge commit the API writes appears a
    # few seconds later), so the head check above saw nothing behind; the new head's ten jobs
    # were all queued. One more poll costs POLL seconds and catches every such lag.
    ghq pr view "$TARGET" -R "$REPO" --json headRefOid --jq .headRefOid || { sleep "$POLL"; continue; }
    if [[ "$gh_out" != "${green_head:-}" ]]; then
      green_head=$gh_out
      sleep "$POLL"; continue
    fi
    echo "CI-WATCH GREEN: $REPO PR #$TARGET — $total checks, none failing"
    exit 0
  fi

  # ref mode: the verdict belongs to the commit the ref points at NOW, across EVERY
  # workflow that ran on it. Until 2026-10-05 this took runs[0] — the newest run of ANY
  # workflow on the branch: measured, a one-minute "dynamic" run on main reported success
  # while the five-minute CI run of the same push was still going and then went red, and
  # a run of an OLDER commit counted for a newer tip. Both read as "main is green".
  # The commits endpoint resolves a branch AND a tag (peeled) to its commit.
  ghq api "repos/$REPO/commits/$TARGET" --jq .sha; sha=$gh_out
  if [[ -z "$sha" ]]; then
    if (( warned_no_run == 0 )); then
      echo "ci-watch: ref '$TARGET' not resolvable on $REPO yet — waiting" >&2
      warned_no_run=1
    fi
    sleep "$POLL"; continue
  fi
  # The ref moved: the run of the old commit is superseded (GitHub cancels it when the
  # workflow uses a concurrency group, or it finishes for a commit nobody asked about).
  # The watch is for "the CI of what the ref points at", so it follows the new commit and
  # restarts its clock — a new commit is a new run. Measured 2026-10-14 (header, point 4).
  if [[ -n "$last_sha" && "$sha" != "$last_sha" ]]; then
    moves=$(( moves + 1 ))
    if (( moves > MOVES_MAX )); then
      fail_unknown "ref '$TARGET' on $REPO moved $moves times during the watch (last ${sha:0:7}) — arm one watch per push, not one watch for a day of merges"
    fi
    echo "ci-watch: ref '$TARGET' moved ${last_sha:0:7} -> ${sha:0:7} — the run of ${last_sha:0:7} is superseded, not a verdict; watching ${sha:0:7}, clock restarted (move $moves of $MOVES_MAX)" >&2
    deadline=$(( $(date +%s) + TIMEOUT ))
    warned_no_run=0
  fi
  last_sha="$sha"
  # The runs of THIS commit, whatever their age. `gh run list --limit 50` read the newest
  # 50 runs of the whole repo: on a day with many PR runs the watched commit's runs fell
  # out of that window, the watch saw "none" and waited out its timeout (measured 2026-10-14).
  if ! ghq api "repos/$REPO/actions/runs?head_sha=$sha&per_page=100" \
        --jq '[.workflow_runs[] | {id: .id, headBranch: .head_branch, headSha: .head_sha, status: .status, conclusion: .conclusion, name: .name, event: .event}]'; then
    json="$gh_out$gh_err"
    # One failed call is weather, not a verdict (measured 2026-10-13: an HTTP 504 on the
    # first poll ended a watch on main as UNKNOWN while the run was green; pr mode already
    # tolerated the same error and this mode gave up at once). Keep polling; only a run of
    # failures is a measurement.
    gh_fail=$(( gh_fail + 1 ))
    if (( gh_fail >= 5 )); then fail_unknown "gh api actions/runs failed $gh_fail times in a row: $(head -c 200 <<<"$json")"; fi
    echo "ci-watch: gh api actions/runs failed ($gh_fail/5) — retrying in ${POLL}s: $(head -c 120 <<<"$json")" >&2
    sleep "$POLL"; continue
  fi
  gh_fail=0
  json=$gh_out
  if ! verdict=$("$PY" -c '
import json, sys
ref, sha = sys.argv[1], sys.argv[2]
# A bare commit sha is no branch name: matching headBranch == ref never hit, and the watch
# waited out its timeout (measured 2026-10-09). A ref that IS the resolved commit matches by sha.
bare = len(ref) >= 7 and all(c in "0123456789abcdef" for c in ref.lower()) and sha.startswith(ref.lower())
# A run triggered by a COMMENT (issue_comment, review events, discussions) carries the head sha
# of the default branch, not of what it reacts to: measured 2026-10-22/23 on the core, 15 such
# runs attached to one main commit over four hours, and the watch armed after that merge saw a
# fresh in_progress run of the tip whenever someone commented on any PR — no verdict in 1800 s
# while the push run had been green since minute one. The verdict belongs to the runs the
# commit itself started; comment-triggered runs are noise on it.
NOISE = {"issue_comment", "pull_request_review", "pull_request_review_comment",
         "discussion", "discussion_comment"}
runs = [r for r in json.load(sys.stdin)
        if r.get("headSha") == sha and (bare or r.get("headBranch") == ref)
        and r.get("event") not in NOISE]
# Two runs of one workflow on one commit: the newer one is the verdict, the older one was
# cancelled by the concurrency group (measured 2026-10-26, a core PR read red on such a pair).
newest = {}
for r in runs:
    k = (r.get("name"), r.get("event"))
    if k not in newest or (r.get("id") or 0) > (newest[k].get("id") or 0):
        newest[k] = r
runs = list(newest.values())
WAITING = {"queued", "pending", "waiting", "requested"}
if not runs:
    print("none - -")
elif all(r.get("status") in WAITING for r in runs if r.get("status") != "completed") \
        and any(r.get("status") != "completed" for r in runs):
    print("found queued -")
elif any(r.get("status") != "completed" for r in runs):
    print("found in_progress -")
else:
    bad = [r.get("conclusion") for r in runs
           if r.get("conclusion") not in ("success", "skipped", "neutral")]
    print("found completed", bad[0] if bad else "success")
' "$TARGET" "$sha" <<<"$json" 2>/dev/null); then
    unparsed=$((unparsed + 1))
    if (( unparsed >= UNPARSED_MAX )); then
      fail_unknown "unparseable gh api actions/runs output on $unparsed polls in a row: $(head -c 200 <<<"$json")"
    fi
    echo "ci-watch: gh api actions/runs output not parseable yet (poll $unparsed of $UNPARSED_MAX) — waiting" >&2
    sleep "$POLL"; continue
  fi
  unparsed=0
  read -r found status conclusion <<<"$verdict"

  if [[ "$found" == "none" ]]; then
    no_ci_check
    if (( warned_no_run == 0 )); then
      echo "ci-watch: no run for ref '$TARGET' yet (a just-pushed tag can take a moment) — waiting" >&2
      warned_no_run=1
    fi
    sleep "$POLL"; continue
  fi
  # A run that waits in the queue has not started: the workflow's concurrency group holds it
  # until the previous run of the ref ends. Measured 2026-10-26 on the core's main: a push run
  # created 21:09, its jobs started 21:34 when the previous run (36 min) finished — the watch
  # armed at 21:09 ended UNKNOWN at 1800 s. Waiting time extends the deadline, as a rate-limit
  # block does; CI_WATCH_QUEUE_CEILING (default 7200 s) ends an endless queue honestly.
  if [[ "$status" == "queued" ]]; then
    queued_total=$(( ${queued_total:-0} + POLL ))
    if (( queued_total > ${CI_WATCH_QUEUE_CEILING:-7200} )); then
      fail_unknown "the run of ${sha:0:7} waited ${queued_total}s in the queue without starting"
    fi
    deadline=$(( deadline + POLL ))
    if (( ${warned_queue:-0} == 0 )); then
      echo "ci-watch: the run of ${sha:0:7} waits in the queue (concurrency) — queue time extends the deadline" >&2
      warned_queue=1
    fi
    sleep "$POLL"; continue
  fi
  if [[ "$status" != "completed" ]]; then sleep "$POLL"; continue; fi
  if [[ "$conclusion" == "cancelled" ]]; then
    # Cancelled is a verdict only while the ref still points at this commit. A run that
    # GitHub cancelled because a newer push superseded it says nothing about the newer
    # commit; the next poll follows the move (above) and judges that one.
    ghq api "repos/$REPO/commits/$TARGET" --jq .sha; sha_now=$gh_out
    if [[ -n "$sha_now" && "$sha_now" != "$sha" ]]; then
      echo "ci-watch: run of ${sha:0:7} cancelled and ref '$TARGET' has moved on to ${sha_now:0:7} — superseded, not red" >&2
      continue
    fi
  fi
  case "$conclusion" in
    success)                    echo "CI-WATCH GREEN: $REPO $TARGET — success"; exit 0 ;;
    failure|cancelled|timed_out|startup_failure|action_required)
                                echo "CI-WATCH RED: $REPO $TARGET — $conclusion"; exit 1 ;;
    skipped|neutral)            echo "CI-WATCH GREEN: $REPO $TARGET — $conclusion (no failing verdict)"; exit 0 ;;
    *)                          fail_unknown "unmapped conclusion '$conclusion' — refusing to guess" ;;
  esac
done
