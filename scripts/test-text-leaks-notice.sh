#!/usr/bin/env bash
# Fixture for scripts/text-leaks-notice.sh — both directions: a finding becomes a notice that
# names class and line and mentions the author, and NEVER carries the matched text (a name,
# an address, a home path); no finding = no notice (empty stdout, exit 0).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails+1)); }
S="$HERE/text-leaks-notice.sh"

# 1. findings of every kind: redacted name, an address printed as matched, a home path
cat > "$T/scan.out" <<'OUT'
leak-scan: 3 findings
!! [person] text:event-text.txt:4: <redacted 5 chars>
!! [private_ip] text:event-text.txt:7: 192.0.2.23
!! [home_path] text:event-text.txt:9: /Users/Shared/nobody
OUT
out="$(AUTHOR=octocat WHAT=issue_comment RUN_URL=https://example.invalid/run/1 bash "$S" "$T/scan.out")"; rc=$?
[ "$rc" = 0 ] && ok "findings: exit 0" || bad "findings: exit $rc"
printf '%s' "$out" | grep -q '^@octocat' && ok "the author is mentioned first" || bad "no @author at the start"
printf '%s' "$out" | grep -q -- '- person at line 4' && ok "class and line of the name finding" || bad "name finding missing"
printf '%s' "$out" | grep -q -- '- private_ip at line 7' && ok "class and line of the address finding" || bad "address finding missing"
printf '%s' "$out" | grep -q -- '- home_path at line 9' && ok "class and line of the home-path finding" || bad "home-path finding missing"
printf '%s' "$out" | grep -q '192\.0\.2\.23' && bad "the matched address is repeated in the notice" || ok "the matched address is NOT in the notice"
printf '%s' "$out" | grep -q '/Users/Shared/nobody' && bad "the matched home path is repeated in the notice" || ok "the matched home path is NOT in the notice"
printf '%s' "$out" | grep -q 'redacted' && bad "the redaction marker leaks into the notice" || ok "no redaction marker in the notice"
printf '%s' "$out" | grep -q 'your comment' && ok "issue_comment reads as a comment" || bad "event kind not named"
printf '%s' "$out" | grep -q 'Run: https://example.invalid/run/1' && ok "the run is linked" || bad "run link missing"

# 2. a review body: kind named, no author/run = no empty mention, no empty link
out="$(AUTHOR='' WHAT=pull_request_review RUN_URL='' bash "$S" "$T/scan.out")"
printf '%s' "$out" | grep -q 'your review names' && ok "review kind named" || bad "review kind not named"
printf '%s' "$out" | grep -q '^@' && bad "an empty author still produced a mention" || ok "no mention without an author"
printf '%s' "$out" | grep -q 'Run:' && bad "an empty run url still produced a link" || ok "no run link without a url"

# 3. no finding: empty stdout, exit 0 (the workflow never posts an empty notice)
printf 'leak-scan: 0 findings\n' > "$T/clean.out"
out="$(bash "$S" "$T/clean.out")"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "clean scan: nothing printed, exit 0" || bad "clean scan: rc=$rc output='$out'"

# 4. unreadable input is loud (exit 2), never a silent empty notice
bash "$S" "$T/missing.out" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "missing scan file: exit 2" || bad "missing scan file: exit $rc"

if [ "$fails" = 0 ]; then echo "test-text-leaks-notice: all checks passed"; else echo "test-text-leaks-notice: $fails check(s) FAILED"; exit 1; fi
