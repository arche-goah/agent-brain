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
  ref_green)  echo '[{"headBranch":"v9.9.9","status":"completed","conclusion":"success"}]' ;;
  ref_red)    echo '[{"headBranch":"v9.9.9","status":"completed","conclusion":"failure"}]' ;;
  ref_absent) echo '[{"headBranch":"main","status":"completed","conclusion":"success"}]' ;;
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
check "gh hard error in ref mode"       gh_broken  2 ref v9.9.9

echo
if (( fails )); then echo "ci-watch-test: $fails FAILURE(S)"; exit 1; fi
echo "ci-watch-test: all 20 checks passed"
