#!/usr/bin/env bash
# test-lint-placeholders.sh - fixture for lint-placeholders.sh: each placeholder class is red, a filled file is green.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
lint="$here/lint-placeholders.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0
check() {  # <name> <expected rc> <file content>
  printf '%s\n' "$3" > "$tmp/case.json"
  bash "$lint" "$tmp/case.json" > /dev/null 2>&1; rc=$?
  if [ "$rc" -eq "$2" ]; then echo "  ok    $1"; else echo "  FAIL  $1 (rc $rc, wanted $2)"; fail=1; fi
}
check "a {DEIN_NAME} placeholder is red" 1 'Hello {DEIN_NAME}'
# 2026-11-20: os-proof.json kept the template's example repo after the copy
check "the os-proof template's example repo is red" 1 '{"ci_counts_as_os_check": {"example-owner/example-repo": ["Windows"]}}'
check "an example server key of mcp-expected is red" 1 '{"example-server": 7}'
check "an example shop of product-sources is red" 1 '{"example-shop.com": "/product/x"}'
check "a filled os-proof is green" 0 '{"ci_counts_as_os_check": {"arche-goah/agent-brain": ["Windows"]}}'
check "the word example inside prose is green" 0 '{"_comment": "for example-style values see the template"}'
[ "$fail" -eq 0 ] && echo "test-lint-placeholders: all cases pass"
exit "$fail"
