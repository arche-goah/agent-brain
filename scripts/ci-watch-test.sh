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
  pr_flip)    f="${CI_WATCH_STATE:?}"
              if [[ -f "$f" ]]; then echo '[{"bucket":"pass"}]'
              else touch "$f"; echo '[{"bucket":"pending"},{"bucket":"pass"}]'; fi ;;
  gh_broken)  echo "HTTP 500 boom" >&2; exit 1 ;;
  ref_green)  echo '[{"headBranch":"v9.9.9","status":"completed","conclusion":"success"}]' ;;
  ref_red)    echo '[{"headBranch":"v9.9.9","status":"completed","conclusion":"failure"}]' ;;
  ref_absent) echo '[{"headBranch":"main","status":"completed","conclusion":"success"}]' ;;
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
check "pr zero checks = unknown"        pr_zero    2 pr 12
check "pr pending then green"           pr_flip    0 pr 12
check "gh hard error = unknown"         gh_broken  2 pr 12
check "ref (tag) success"               ref_green  0 ref v9.9.9
check "ref (tag) failure"               ref_red    1 ref v9.9.9
check "ref never appears = timeout(2)"  ref_absent 2 ref v9.9.9 2
check "gh hard error in ref mode"       gh_broken  2 ref v9.9.9

echo
if (( fails )); then echo "ci-watch-test: $fails FAILURE(S)"; exit 1; fi
echo "ci-watch-test: all 9 fixtures passed"
