#!/usr/bin/env bash
# ci-watch-test.sh — both-direction fixtures for ci-watch.sh with a stubbed gh.
# A watcher that can only turn green is wallpaper: every exit class (0 green,
# 1 red, 2 unknown) is proven here, including the two field failures that
# motivated the tool (tag ref invisible to --branch, silent empty result).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- gh stub: behavior selected via CI_WATCH_STUB, state kept in $TMP ---------
cat > "$TMP/gh" <<'STUB'
#!/usr/bin/env bash
case "${CI_WATCH_STUB:?}" in
  pr_green)   echo '[{"bucket":"pass"},{"bucket":"skipping"}]' ;;
  pr_red)     echo '[{"bucket":"pass"},{"bucket":"fail"}]' ;;
  pr_zero)    echo '[]' ;;
  # gh's wording when the run has not been created yet. rc=1, not rc=8.
  pr_nochecks) echo "no checks reported on the 'feature' branch" >&2; exit 1 ;;
  # the race that motivated the wait: not-yet on the first poll, checks on the second.
  pr_nochecks_flip)
              f="${CI_WATCH_STATE:?}"
              if [[ -f "$f" ]]; then echo '[{"bucket":"pass"}]'
              else touch "$f"; echo "no checks reported on the 'feature' branch" >&2; exit 1; fi ;;
  pr_flip)    f="${CI_WATCH_STATE:?}"
              if [[ -f "$f" ]]; then echo '[{"bucket":"pass"}]'
              else touch "$f"; echo '[{"bucket":"pending"},{"bucket":"pass"}]'; fi ;;
  gh_broken)  echo "HTTP 500 boom" >&2; exit 1 ;;
  # 2026-10-10: right after a merge, `pr checks` answered with exit 0 and a reply that was not
  # the JSON list (the run was being registered); the next poll had 11 green checks. One
  # unparseable poll is a wait; only a repeat is a verdict.
  pr_garbage_flip) f="${CI_WATCH_STATE:?}"
              if [[ -f "$f" ]]; then echo '[{"bucket":"pass"}]'
              else touch "$f"; echo 'Checks are being registered'; fi ;;
  pr_garbage) echo 'Checks are being registered' ;;
  ref_garbage_flip) [[ "$*" == */commits/* ]] && { echo abc123; exit 0; }
              f="${CI_WATCH_STATE:?}"
              if [[ -f "$f" ]]; then echo '[{"headBranch":"v9.9.9","headSha":"abc123","status":"completed","conclusion":"success"}]'
              else touch "$f"; echo 'not json'; fi ;;
  # Ref mode resolves the ref's commit via `gh api repos/<r>/commits/<ref>` first, then
  # reads that commit's runs via `gh api repos/<r>/actions/runs?head_sha=<sha>` (2026-10-14;
  # before: the newest 50 runs of the repo, which a busy day pushed the commit out of).
  ref_green)  [[ "$*" == */commits/* ]] && { echo abc123; exit 0; }
              echo '[{"headBranch":"v9.9.9","headSha":"abc123","status":"completed","conclusion":"success"}]' ;;
  ref_red)    [[ "$*" == */commits/* ]] && { echo abc123; exit 0; }
              echo '[{"headBranch":"v9.9.9","headSha":"abc123","status":"completed","conclusion":"failure"}]' ;;
  ref_absent) [[ "$*" == */commits/* ]] && { echo abc123; exit 0; }
              echo '[{"headBranch":"main","headSha":"abc123","status":"completed","conclusion":"success"}]' ;;
  # 2026-10-05: a fast second workflow finished green on the same push while CI went red.
  # The old code took runs[0] (newest of ANY workflow) and said green.
  ref_mixed)  [[ "$*" == */commits/* ]] && { echo abc123; exit 0; }
              echo '[{"headBranch":"main","headSha":"abc123","status":"completed","conclusion":"success","name":"dynamic"},
                     {"headBranch":"main","headSha":"abc123","status":"completed","conclusion":"failure","name":"CI"}]' ;;
  # ...and a green run of an OLDER commit must not count for the current tip.
  ref_oldsha) [[ "$*" == */commits/* ]] && { echo new999; exit 0; }
              echo '[{"headBranch":"main","headSha":"old111","status":"completed","conclusion":"success"}]' ;;
  # 2026-10-09: a bare commit sha as ref — runs carry a branch name, never the sha, so
  # matching on headBranch alone waited out every timeout.
  ref_sha)    [[ "$*" == */commits/* ]] && { echo abc1234def0; exit 0; }
              echo '[{"headBranch":"main","headSha":"abc1234def0","status":"completed","conclusion":"success"}]' ;;
  ref_sha_red) [[ "$*" == */commits/* ]] && { echo abc1234def0; exit 0; }
              echo '[{"headBranch":"main","headSha":"abc1234def0","status":"completed","conclusion":"failure"}]' ;;
  # one workflow of the tip still running: not a verdict yet.
  ref_partial) [[ "$*" == */commits/* ]] && { echo abc123; exit 0; }
              echo '[{"headBranch":"main","headSha":"abc123","status":"completed","conclusion":"success","name":"dynamic"},
                     {"headBranch":"main","headSha":"abc123","status":"in_progress","conclusion":"","name":"CI"}]' ;;
  # 2026-10-14: the ref moves while watched. First poll resolves old111, whose run GitHub
  # cancelled for the newer push; from then on the ref is new222 and its run is green.
  # A cancelled run of a commit the ref has left is superseded, not red; the watch follows.
  ref_superseded) f="${CI_WATCH_STATE:?}"
              if [[ "$*" == */commits/* ]]; then
                if [[ -f "$f" ]]; then echo new222; else touch "$f"; echo old111; fi; exit 0; fi
              if [[ "$*" == *head_sha=old111* ]]; then echo '[{"headBranch":"main","headSha":"old111","status":"completed","conclusion":"cancelled","name":"CI"}]'
              else echo '[{"headBranch":"main","headSha":"new222","status":"completed","conclusion":"success","name":"CI"}]'; fi ;;
  # ...control: cancelled while the ref STILL points at the commit is a real red.
  ref_cancelled_stays) [[ "$*" == */commits/* ]] && { echo abc123; exit 0; }
              echo '[{"headBranch":"main","headSha":"abc123","status":"completed","conclusion":"cancelled","name":"CI"}]' ;;
  # ...and a ref that never stops moving must not restart its clock forever.
  ref_moves_forever) f="${CI_WATCH_STATE:?}"
              if [[ "$*" == */commits/* ]]; then
                n=$(cat "$f" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" >"$f"; echo "sha00$n"; exit 0; fi
              echo '[{"headBranch":"main","headSha":"x","status":"in_progress","conclusion":"","name":"CI"}]' ;;
  # A conflicted PR: `pr checks` sees nothing (GitHub never creates the run),
  # `pr view --json mergeable` names the reason. Two flavors: gh error wording / empty list.
  pr_conflict)      if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then echo "CONFLICTING"
                    else echo "no checks reported on the 'feature' branch" >&2; exit 1; fi ;;
  pr_conflict_zero) if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then echo "CONFLICTING"
                    else echo '[]'; fi ;;
  # The stale-field race: mergeable reads CONFLICTING once right after a push, then
  # heals; the checks appear a round later. ONE stale read must not kill the watch.
  pr_conflict_stale)
                    f="${CI_WATCH_STATE:?}"
                    if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
                      if [[ -f "$f.view" ]]; then echo "MERGEABLE"
                      else touch "$f.view"; echo "CONFLICTING"; fi
                    else
                      if [[ -f "$f.view" ]]; then echo '[{"bucket":"pass"}]'
                      else echo "no checks reported on the 'feature' branch" >&2; exit 1; fi
                    fi ;;
  # The live case of 2026-09-02: ALL checks green, but they predate the base change —
  # the PR is genuinely conflicting and a merge would 405. Green must not exit 0 here.
  pr_green_conflict) if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then echo "CONFLICTING"
                    else echo '[{"bucket":"pass"},{"bucket":"pass"}]'; fi ;;
  # ...and the same shape where the CONFLICTING read was just stale: heals to green.
  pr_green_conflict_stale)
                    f="${CI_WATCH_STATE:?}"
                    if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
                      if [[ -f "$f.view" ]]; then echo "MERGEABLE"
                      else touch "$f.view"; echo "CONFLICTING"; fi
                    else echo '[{"bucket":"pass"}]'; fi ;;
  # 2026-10-11: a repo with no workflow at all looks like "not registered yet" forever.
  # `gh api repos/<r>/actions/workflows --jq .total_count` is the one question that tells them apart.
  pr_noci)          if [[ "${1:-}" == api ]]; then echo 0; else echo '[]'; fi ;;
  pr_noci_nochecks) if [[ "${1:-}" == api ]]; then echo 0
                    else echo "no checks reported on the 'feature' branch" >&2; exit 1; fi ;;
  # negative controls: workflows exist (2) / the count cannot be read — keep waiting.
  pr_zero_hasci)    if [[ "${1:-}" == api ]]; then echo 2; else echo '[]'; fi ;;
  pr_zero_apierr)   if [[ "${1:-}" == api ]]; then echo "HTTP 403" >&2; exit 1; else echo '[]'; fi ;;
  ref_noci)         if [[ "${1:-}" == api && "${2:-}" == */actions/workflows ]]; then echo 0
                    elif [[ "$*" == */commits/* ]]; then echo abc123
                    else echo '[]'; fi ;;
  # 2026-10-12: GitHub left a check-run at status=in_progress WITH conclusion=success
  # (measured on a suite PR; its workflow run was completed). `pr checks` buckets it as
  # pending forever; the head commit's check-runs carry the conclusion. The verdict must
  # come from the FIRST poll: a second `pr checks` call makes the stub fail hard.
  pr_stale_green|pr_stale_red|pr_stale_running)
                    f="${CI_WATCH_STATE:?}"
                    case "$CI_WATCH_STUB" in pr_stale_green) c='"success"' ;; pr_stale_red) c='"failure"' ;; *) c=null ;; esac
                    if [[ "$*" == *headRefOid* ]]; then echo 3429ad2e44c66a393de8354938717ffafaf6d26b
                    elif [[ "${1:-}" == pr && "${2:-}" == view ]]; then echo MERGEABLE
                    elif [[ "${1:-}" == api ]]; then echo '[{"name":"test","conclusion":"success"},{"name":"release-preflight","conclusion":'"$c"'}]'
                    elif [[ "$CI_WATCH_STUB" != pr_stale_running && -f "$f" ]]; then echo "second poll reached" >&2; exit 1
                    else touch "$f"; echo '[{"bucket":"pass","name":"test"},{"bucket":"pending","name":"release-preflight"}]'; fi ;;
  # 2026-10-16: the listed checks are all green, but a second workflow run of the head commit
  # is in_progress and has not listed its jobs yet. pr_run_open: it stays open (no verdict);
  # pr_run_flip: it completes on the second read (then green).
  pr_run_open|pr_run_flip)
                    f="${CI_WATCH_STATE:?}"
                    if [[ "$*" == *headRefOid* ]]; then echo 3429ad2e44c66a393de8354938717ffafaf6d26b
                    elif [[ "${1:-}" == pr && "${2:-}" == view ]]; then echo MERGEABLE
                    elif [[ "${1:-}" == api && "$*" == *actions/runs* ]]; then
                      if [[ "$CI_WATCH_STUB" == pr_run_flip && -f "$f" ]]; then echo 0; else touch "$f"; echo 1; fi
                    else echo '[{"bucket":"pass","name":"CodeQL"},{"bucket":"pass","name":"Analyze"}]'; fi ;;
  # 2026-10-16: right after a push the PR still shows the OLD head and its green checks.
  # pr_head_lag: the head flips to the pushed commit on the second read; pr_head_stuck: never.
  pr_head_lag|pr_head_stuck)
                    f="${CI_WATCH_STATE:?}"
                    if [[ "$*" == *headRefOid* ]]; then
                      if [[ "$CI_WATCH_STUB" == pr_head_lag && -f "$f" ]]; then echo bbbb222200000000000000000000000000000000
                      else touch "$f"; echo aaaa111100000000000000000000000000000000; fi
                    elif [[ "${1:-}" == pr && "${2:-}" == view ]]; then echo MERGEABLE
                    elif [[ "${1:-}" == api ]]; then echo 0
                    else echo '[{"bucket":"pass","name":"lint"}]'; fi ;;
  # ...and a pending entry that is a commit STATUS (no check-run of that name) keeps waiting.
  pr_stale_status)  if [[ "$*" == *headRefOid* ]]; then echo 3429ad2e44c66a393de8354938717ffafaf6d26b
                    elif [[ "${1:-}" == pr && "${2:-}" == view ]]; then echo MERGEABLE
                    elif [[ "${1:-}" == api ]]; then echo '[{"name":"test","conclusion":"success"}]'
                    else echo '[{"bucket":"pass","name":"test"},{"bucket":"pending","name":"ci/external"}]'; fi ;;
  # 2026-10-19: GitHub's rate limit (three sessions, one account). `pr checks` answers by the
  # comma list CI_WATCH_RL_SEQ, one element per call, the last one repeating:
  # rl = primary wording, rl2 = secondary wording (HTTP 403), pending, green.
  # `gh api rate_limit` names an exhausted resource's reset only when CI_WATCH_RL_PRIMARY is set.
  pr_rl)            f="${CI_WATCH_STATE:?}"
                    if [[ "$*" == *rate_limit* ]]; then [[ -n "${CI_WATCH_RL_PRIMARY:-}" ]] && date +%s; exit 0; fi
                    if [[ "${1:-}" == pr && "${2:-}" == checks ]]; then
                      n=$(cat "$f" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" >"$f"
                      IFS=, read -r -a seq <<<"${CI_WATCH_RL_SEQ:?}"
                      s=${seq[n-1]:-${seq[${#seq[@]}-1]}}
                      case "$s" in
                        rl)      echo "GraphQL: API rate limit already exceeded for user ID 1234." >&2; exit 1 ;;
                        rl2)     echo "HTTP 403: You have exceeded a secondary rate limit. Please wait a few minutes before you try again." >&2; exit 1 ;;
                        pending) echo '[{"bucket":"pending","name":"lint"}]' ;;
                        green)   echo '[{"bucket":"pass","name":"lint"}]' ;;
                      esac
                    elif [[ "$*" == *headRefOid* ]]; then echo 3429ad2e44c66a393de8354938717ffafaf6d26b
                    elif [[ "${1:-}" == pr && "${2:-}" == view ]]; then echo MERGEABLE
                    else echo 0; fi ;;
  # ...the same on a call whose errors the watch swallows (mergeable): two blocked reads, then fine.
  pr_rl_view)       f="${CI_WATCH_STATE:?}"
                    if [[ "$*" == *rate_limit* ]]; then exit 0; fi
                    if [[ "$*" == *mergeable* ]]; then
                      n=$(cat "$f" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" >"$f"
                      if (( n <= 2 )); then echo "HTTP 429: Too Many Requests" >&2; exit 1; fi
                      echo MERGEABLE
                    elif [[ "$*" == *headRefOid* ]]; then echo 3429ad2e44c66a393de8354938717ffafaf6d26b
                    elif [[ "${1:-}" == api ]]; then echo 0
                    else echo '[{"bucket":"pass","name":"lint"}]'; fi ;;
  # ...and in ref mode: six rate-limited reads of the runs (the old code gave up after five).
  ref_rl)           f="${CI_WATCH_STATE:?}"
                    if [[ "$*" == *rate_limit* ]]; then exit 0; fi
                    [[ "$*" == */commits/* ]] && { echo abc123; exit 0; }
                    n=$(cat "$f" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" >"$f"
                    if (( n <= 6 )); then echo "gh: API rate limit exceeded for user ID 1234. (HTTP 403)" >&2; exit 1; fi
                    echo '[{"headBranch":"main","headSha":"abc123","status":"completed","conclusion":"success","name":"CI"}]' ;;
  # 2026-10-19: right after a push the PR still lists the OLD head (aaaa…) and its RED checks,
  # while the branch ref is already at the pushed commit (bbbb…). pr_tip_lag: the PR catches up
  # on the second read and its checks are green; pr_tip_stuck: it never catches up;
  # pr_tip_synced_red: control — PR head == branch tip, the red is real.
  pr_tip_lag|pr_tip_stuck|pr_tip_synced_red)
                    f="${CI_WATCH_STATE:?}"
                    old=aaaa111100000000000000000000000000000000; new=bbbb222200000000000000000000000000000000
                    if [[ "$CI_WATCH_STUB" == pr_tip_synced_red ]]; then old=$new; fi
                    if [[ "$*" == *headRefName* ]]; then
                      if [[ "$CI_WATCH_STUB" == pr_tip_lag && -f "$f" ]]; then printf '%s\tfeature\towner/repo\n' "$new"
                      else touch "$f"; printf '%s\tfeature\towner/repo\n' "$old"; fi
                    elif [[ "$*" == *git/ref/heads/feature* ]]; then echo "$new"
                    elif [[ "${1:-}" == pr && "${2:-}" == view ]]; then echo MERGEABLE
                    elif [[ "${1:-}" == api ]]; then echo 0
                    elif [[ "$CI_WATCH_STUB" == pr_tip_lag && -f "$f" ]]; then echo '[{"bucket":"pass","name":"lint"}]'
                    else echo '[{"bucket":"pass","name":"lint"},{"bucket":"fail","name":"test"}]'; fi ;;
esac
STUB
chmod +x "$TMP/gh"
# Fake clock for cases that must not depend on real runtime: with CI_WATCH_FAKE_CLOCK set,
# `sleep N` returns at once and advances an offset that `date +%s` adds to the real time.
# Unset, both pass straight through to the real commands.
REAL_DATE=$(command -v date); REAL_SLEEP=$(command -v sleep)
export REAL_DATE REAL_SLEEP
cat > "$TMP/date" <<'STUB'
#!/usr/bin/env bash
if [[ -n "${CI_WATCH_FAKE_CLOCK:-}" && "$*" == "+%s" ]]; then
  echo $(( $("$REAL_DATE" +%s) + $(cat "$CI_WATCH_FAKE_CLOCK" 2>/dev/null || echo 0) ))
else exec "$REAL_DATE" "$@"; fi
STUB
cat > "$TMP/sleep" <<'STUB'
#!/usr/bin/env bash
if [[ -n "${CI_WATCH_FAKE_CLOCK:-}" ]]; then
  o=$(cat "$CI_WATCH_FAKE_CLOCK" 2>/dev/null || echo 0); echo $(( o + ${1%%.*} )) >"$CI_WATCH_FAKE_CLOCK"
else exec "$REAL_SLEEP" "$@"; fi
STUB
chmod +x "$TMP/date" "$TMP/sleep"
export PATH="$TMP:$PATH"
export CI_WATCH_POLL=0
# Rate-limit waits in the fixtures: no backoff, no reset slack (a case that needs real time sets its own).
export CI_WATCH_RL_BACKOFF=0 CI_WATCH_RL_MARGIN=0
# The script under test; point it at an older copy to run the fixtures as a negative control.
WATCH="${CI_WATCH_SCRIPT:-$HERE/ci-watch.sh}"

fails=0
check() { # label scenario expected_rc mode target timeout
  local label="$1" scen="$2" want="$3" mode="$4" target="$5" to="${6:-5}"
  rm -f "$TMP/state-$scen" "$TMP/state-$scen".*   # each case starts from a fresh stub state
  CI_WATCH_STUB="$scen" CI_WATCH_STATE="$TMP/state-$scen" \
    bash "$WATCH" "$mode" owner/repo "$target" "$to" >"$TMP/out" 2>&1
  local got=$?
  if [[ "$got" == "$want" ]]; then echo "  OK   $label (rc=$got)"
  else echo "  FAIL $label: rc=$got wanted $want"; sed 's/^/       /' "$TMP/out"; fails=$((fails+1)); fi
}

echo "=== ci-watch fixtures ==="
check "pr all green"                    pr_green   0 pr 12
check "pr one failing check"            pr_red     1 pr 12
check "pr zero checks = wait, then timeout(2)"  pr_zero          2 pr 12 2
check "pr 'no checks reported' waits, then timeout(2)" pr_nochecks 2 pr 12 2
check "pr 'no checks' then green"       pr_nochecks_flip 0 pr 12
check "pr pending then green"           pr_flip    0 pr 12
check "gh hard error = unknown"         gh_broken  2 pr 12
check "pr unparseable once, then green" pr_garbage_flip 0 pr 12
check "pr unparseable three polls = unknown(2)" pr_garbage 2 pr 12 30
grep -q "3 polls in a row" "$TMP/out" && echo "  OK   unknown names the repeated unparseable reply" \
  || { echo "  FAIL unknown verdict does not name the repeat"; fails=$((fails+1)); }
check "ref unparseable once, then green" ref_garbage_flip 0 ref v9.9.9
check "conflicted PR (no-checks wording) = named unknown(2), no wait" pr_conflict      2 pr 12 30
grep -q "CONFLICTING" "$TMP/out" && echo "  OK   conflict verdict names CONFLICTING" \
  || { echo "  FAIL conflict verdict does not name CONFLICTING"; fails=$((fails+1)); }
check "conflicted PR (zero checks) = named unknown(2), no wait"       pr_conflict_zero 2 pr 12 30
grep -q "rebase" "$TMP/out" && echo "  OK   conflict verdict says rebase" \
  || { echo "  FAIL conflict verdict does not say rebase"; fails=$((fails+1)); }
check "ONE stale CONFLICTING read heals, watch turns green"           pr_conflict_stale 0 pr 12
grep -q "two consecutive reads" "$TMP/out" && { echo "  FAIL stale single read produced the verdict"; fails=$((fails+1)); } \
  || echo "  OK   single stale read did not verdict"
check "green checks + real conflict = unknown(2), NOT green"          pr_green_conflict 2 pr 12 30
grep -q "STALE" "$TMP/out" && echo "  OK   green-but-conflicting verdict names stale checks" \
  || { echo "  FAIL verdict does not explain stale green checks"; fails=$((fails+1)); }
check "green checks + stale conflict read heals to green"             pr_green_conflict_stale 0 pr 12
check "ref (tag) success"               ref_green  0 ref v9.9.9
check "ref (tag) failure"               ref_red    1 ref v9.9.9
check "ref never appears = timeout(2)"  ref_absent 2 ref v9.9.9 2
check "ref: green side-workflow + red CI on the same commit = RED"  ref_mixed   1 ref main
check "ref: green run of an OLDER commit does not count = timeout(2)" ref_oldsha 2 ref main 2
check "ref: one workflow of the tip still running = no verdict, timeout(2)" ref_partial 2 ref main 2
check "ref: bare commit sha, run green = GREEN"  ref_sha     0 ref abc1234
check "ref: bare commit sha, run red = RED"      ref_sha_red 1 ref abc1234
check "ref: cancelled run of a superseded commit, green tip = GREEN" ref_superseded 0 ref main
grep -q "superseded, not red" "$TMP/out" && echo "  OK   superseded run is named, not judged" \
  || { echo "  FAIL superseded run not named"; fails=$((fails+1)); }
grep -q "clock restarted (move 1 of" "$TMP/out" && echo "  OK   the move restarts the clock and is counted" \
  || { echo "  FAIL move not logged with a restarted clock"; fails=$((fails+1)); }
check "ref: cancelled while the ref still points at it = RED (control)" ref_cancelled_stays 1 ref main
check "ref: ref keeps moving = unknown(2) naming the moves" ref_moves_forever 2 ref main 30
grep -q "moved 6 times" "$TMP/out" && echo "  OK   endless moves end as UNKNOWN naming the count" \
  || { echo "  FAIL endless moves not named"; fails=$((fails+1)); }
check "gh hard error in ref mode"       gh_broken  2 ref v9.9.9
check "pr: repo without workflows = NO-CI(3) at once" pr_noci          3 pr 12 30
grep -q "not green" "$TMP/out" && echo "  OK   no-CI verdict says not green" \
  || { echo "  FAIL no-CI verdict does not say not green"; fails=$((fails+1)); }
check "pr: 'no checks' wording + no workflows = NO-CI(3)" pr_noci_nochecks 3 pr 12 30
check "pr: zero checks, workflows exist = wait, timeout(2)" pr_zero_hasci 2 pr 12 2
check "pr: zero checks, count unreadable = wait, timeout(2)" pr_zero_apierr 2 pr 12 2
check "ref: repo without workflows = NO-CI(3)"         ref_noci        3 ref main 30
check "pr: stale check-run (in_progress + conclusion success) = GREEN on the first poll" pr_stale_green 0 pr 12 30
grep -q "left the status stale" "$TMP/out" && echo "  OK   stale check-run is named in the output" \
  || { echo "  FAIL stale check-run not named"; fails=$((fails+1)); }
check "pr: stale check-run with conclusion failure = RED"           pr_stale_red     1 pr 12 30
check "pr: check-run genuinely running (conclusion null) = wait, timeout(2)" pr_stale_running 2 pr 12 2
grep -q "left the status stale" "$TMP/out" && { echo "  FAIL running check-run was called stale"; fails=$((fails+1)); } \
  || echo "  OK   running check-run was not called stale"
check "pr: pending commit status without a check-run = wait, timeout(2)" pr_stale_status 2 pr 12 2
check "pr: listed checks green, a workflow run still open = wait, timeout(2)" pr_run_open 2 pr 12 2
check "pr: listed checks green, the open run completes = GREEN"          pr_run_flip 0 pr 12 30
CI_WATCH_SHA=bbbb2222 check "pr: CI_WATCH_SHA, head still old, then flips = GREEN on the new head" pr_head_lag 0 pr 12 30
CI_WATCH_SHA=bbbb2222 check "pr: CI_WATCH_SHA, head never reaches it = wait, timeout(2)"   pr_head_stuck 2 pr 12 2
check "pr: without CI_WATCH_SHA the old head's green counts (unchanged behaviour)"        pr_head_stuck 0 pr 12 30
check "pr: PR head behind its branch tip, old head red, then catches up green = GREEN"  pr_tip_lag 0 pr 12 30
grep -q "has not caught up with" "$TMP/out" && echo "  OK   the lagging head is named" \
  || { echo "  FAIL lagging head not named"; fails=$((fails+1)); }
check "pr: PR head never reaches its branch tip, old head red = no verdict, timeout(2)" pr_tip_stuck 2 pr 12 2
grep -q "CI-WATCH RED" "$TMP/out" && { echo "  FAIL the old head's red was reported"; fails=$((fails+1)); } \
  || echo "  OK   the old head's red was not reported"
check "pr: PR head == branch tip, red = RED (control)"                                    pr_tip_synced_red 1 pr 12 30

# Rate limit (2026-10-19): a blocked answer is a wait, never a verdict and never an early exit.
blocked_is() { # label n — the last run printed exactly n BLOCKED lines
  local got; got=$(grep -c '^CI-WATCH BLOCKED: GitHub API rate limit — waiting until' "$TMP/out")
  if [[ "$got" == "$2" ]]; then echo "  OK   $1 ($got BLOCKED line(s))"
  else echo "  FAIL $1: $got BLOCKED line(s), wanted $2"; sed 's/^/       /' "$TMP/out"; fails=$((fails+1)); fi
}
CI_WATCH_RL_SEQ=rl,rl,rl,green check "pr: three rate-limited answers (secondary), then green = GREEN" pr_rl 0 pr 12 30
blocked_is "one block, one BLOCKED line" 1
grep -q "polling resumed" "$TMP/out" && echo "  OK   the end of the block is named" \
  || { echo "  FAIL end of block not named"; fails=$((fails+1)); }
CI_WATCH_RL_PRIMARY=1 CI_WATCH_RL_SEQ=rl,green check "pr: primary limit exhausted, wait for its reset, then green = GREEN" pr_rl 0 pr 12 30
grep -q "primary limit exhausted, reset" "$TMP/out" && echo "  OK   the primary reset is what the wait follows" \
  || { echo "  FAIL primary reset not used"; fails=$((fails+1)); }
CI_WATCH_RL_SEQ=rl2,pending,rl2,rl2,green check "pr: two separate blocks (secondary wording, HTTP 403) = GREEN" pr_rl 0 pr 12 30
blocked_is "two blocks, two BLOCKED lines" 2
# The blocked time must not eat the verdict timeout: a block of 600-750 s (fake clock — no real
# waiting, so a slow runner cannot flip it) against a 60 s timeout, then one more poll after it.
# Counted against the timeout, this ends UNKNOWN; the real runtime only has to stay under 60 s.
rm -f "$TMP/fakeclock"
CI_WATCH_FAKE_CLOCK="$TMP/fakeclock" CI_WATCH_RL_BACKOFF=600 CI_WATCH_RL_SEQ=rl,pending,green \
  check "pr: a block longer than the timeout extends the deadline = GREEN" pr_rl 0 pr 12 60
grep -q "next try\|waiting until" "$TMP/out" && [[ $(cat "$TMP/fakeclock") -ge 600 ]] \
  && echo "  OK   the fake clock advanced past the timeout ($(cat "$TMP/fakeclock")s blocked)" \
  || { echo "  FAIL fake clock did not advance past the timeout"; fails=$((fails+1)); }
CI_WATCH_RL_CEILING=0 CI_WATCH_RL_SEQ=rl check "pr: rate-limited past the ceiling = UNKNOWN(2)" pr_rl 2 pr 12 30
grep -q "rate-limited for .*do NOT read as green" "$TMP/out" && echo "  OK   ceiling verdict names the block and says not green" \
  || { echo "  FAIL ceiling verdict not named"; fails=$((fails+1)); }
blocked_is "ceiling: BLOCKED announced before giving up" 1
check "pr: rate-limited mergeable read (errors swallowed there) = waits, GREEN" pr_rl_view 0 pr 12 30
blocked_is "a swallowed call's block is announced too" 1
check "ref: six rate-limited runs reads, then green = GREEN" ref_rl 0 ref main 30
blocked_is "ref: one block, one BLOCKED line" 1

echo
if (( fails )); then echo "ci-watch-test: $fails FAILURE(S)"; exit 1; fi
echo "ci-watch-test: all checks passed"
