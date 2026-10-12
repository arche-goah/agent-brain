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
  # Ref mode resolves the ref's commit via `gh api repos/<r>/commits/<ref>` first.
  ref_green)  [[ "${1:-}" == api ]] && { echo abc123; exit 0; }
              echo '[{"headBranch":"v9.9.9","headSha":"abc123","status":"completed","conclusion":"success"}]' ;;
  ref_red)    [[ "${1:-}" == api ]] && { echo abc123; exit 0; }
              echo '[{"headBranch":"v9.9.9","headSha":"abc123","status":"completed","conclusion":"failure"}]' ;;
  ref_absent) [[ "${1:-}" == api ]] && { echo abc123; exit 0; }
              echo '[{"headBranch":"main","headSha":"abc123","status":"completed","conclusion":"success"}]' ;;
  # 2026-10-05: a fast second workflow finished green on the same push while CI went red.
  # The old code took runs[0] (newest of ANY workflow) and said green.
  ref_mixed)  [[ "${1:-}" == api ]] && { echo abc123; exit 0; }
              echo '[{"headBranch":"main","headSha":"abc123","status":"completed","conclusion":"success","name":"dynamic"},
                     {"headBranch":"main","headSha":"abc123","status":"completed","conclusion":"failure","name":"CI"}]' ;;
  # ...and a green run of an OLDER commit must not count for the current tip.
  ref_oldsha) [[ "${1:-}" == api ]] && { echo new999; exit 0; }
              echo '[{"headBranch":"main","headSha":"old111","status":"completed","conclusion":"success"}]' ;;
  # 2026-10-09: a bare commit sha as ref — runs carry a branch name, never the sha, so
  # matching on headBranch alone waited out every timeout.
  ref_sha)    [[ "${1:-}" == api ]] && { echo abc1234def0; exit 0; }
              echo '[{"headBranch":"main","headSha":"abc1234def0","status":"completed","conclusion":"success"}]' ;;
  ref_sha_red) [[ "${1:-}" == api ]] && { echo abc1234def0; exit 0; }
              echo '[{"headBranch":"main","headSha":"abc1234def0","status":"completed","conclusion":"failure"}]' ;;
  # one workflow of the tip still running: not a verdict yet.
  ref_partial) [[ "${1:-}" == api ]] && { echo abc123; exit 0; }
              echo '[{"headBranch":"main","headSha":"abc123","status":"completed","conclusion":"success","name":"dynamic"},
                     {"headBranch":"main","headSha":"abc123","status":"in_progress","conclusion":"","name":"CI"}]' ;;
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
                    elif [[ "${1:-}" == api ]]; then echo abc123
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
  # ...and a pending entry that is a commit STATUS (no check-run of that name) keeps waiting.
  pr_stale_status)  if [[ "$*" == *headRefOid* ]]; then echo 3429ad2e44c66a393de8354938717ffafaf6d26b
                    elif [[ "${1:-}" == pr && "${2:-}" == view ]]; then echo MERGEABLE
                    elif [[ "${1:-}" == api ]]; then echo '[{"name":"test","conclusion":"success"}]'
                    else echo '[{"bucket":"pass","name":"test"},{"bucket":"pending","name":"ci/external"}]'; fi ;;
esac
STUB
chmod +x "$TMP/gh"
export PATH="$TMP:$PATH"
export CI_WATCH_POLL=0

fails=0
check() { # label scenario expected_rc mode target timeout
  local label="$1" scen="$2" want="$3" mode="$4" target="$5" to="${6:-5}"
  CI_WATCH_STUB="$scen" CI_WATCH_STATE="$TMP/state-$scen" \
    bash "$HERE/ci-watch.sh" "$mode" owner/repo "$target" "$to" >"$TMP/out" 2>&1
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

echo
if (( fails )); then echo "ci-watch-test: $fails FAILURE(S)"; exit 1; fi
echo "ci-watch-test: all 30 checks passed"
