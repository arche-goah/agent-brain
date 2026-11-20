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
# macOS instance's review of #624: the <...> form of collab-watch.json and its siblings
check "a <owner>/<core-repo> repo of collab-watch is red" 1 '{"repo_watches": [{ "tag": "core", "repos": ["<owner>/<core-repo>"], "interval": 60 }]}'
check "a <operator>-<machine-1> id is red" 1 '{"parties": [{ "id": "<operator>-<machine-1>", "github": "<operator-login>" }]}'
check "a <placeholder> in a string with spaces (prose) is green" 0 '{"stattdessen": "run ci-watch.sh pr <owner/repo> <nr> via Monitor"}'
check "a <placeholder> in a _comment is green" 0 '{"_comment": "replace every <placeholder> - the plan step refuses"}'
check "an escaped quote in prose is green" 0 '{"_comment": ["Map: \"<owner/repo>\": [<OS>, ...] - the systems"]}'
# second review of #624: an inert _example block laid out one object per line (shared-memory-channels.json)
check "an _example_ array, one object per line, is green" 0 '{
  "channels": [],
  "_example_channels": [
    { "label": "devices", "repo": "~/Projects/<private-device-repo>", "members": ["person:<operator>"] },
    { "label": "<group>", "repo": "~/Projects/<group-repo>", "members": ["<device-a>"], "interval": 60 }
  ]
}'
check "the same block as a live key is red" 1 '{"channels": [{ "label": "<group>", "repo": "~/Projects/<group-repo>" }]}'
check "a <placeholder> used as a key is red" 1 '{"ci_counts_as_os_check": {"<owner>/<repo>": ["Windows"]}}'
printf '%s\n' 'Run `tidy.py check "<projekt>"` first.' > "$tmp/case.md"
bash "$lint" "$tmp/case.md" > /dev/null 2>&1 && echo "  ok    a <placeholder> in Markdown is green (JSON only)" \
  || { echo "  FAIL  a <placeholder> in Markdown is red"; fail=1; }
[ "$fail" -eq 0 ] && echo "test-lint-placeholders: all cases pass"
exit "$fail"
