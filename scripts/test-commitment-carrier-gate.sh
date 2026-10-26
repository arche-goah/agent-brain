#!/usr/bin/env bash
# Fixtures for helpers/commitment-carrier-gate.cjs — real promise shapes from 2026-10-26 (translated where
# German): a promise answered by a protocol entry must block, a promise answered by a gate must pass.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
gate="$here/../helpers/commitment-carrier-gate.cjs"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
mkdir -p "$tmp/.claude/rules"
# instance phrasing comes from data: a made-up instance word stands in for a second language
printf '{"patterns":["\\\\bhenceforth\\\\b"],"first_person":["\\\\b(I|we)\\\\b"]}\n' > "$tmp/.claude/rules/commitments.json"

turn() {   # turn <file> <user text> <assistant-json-content...>
  local f=$1; shift
  { printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$(node -e 'console.log(JSON.stringify(process.argv[1]))' "$1")"; shift
    for c in "$@"; do printf '{"type":"assistant","message":{"role":"assistant","content":%s}}\n' "$c"; done; } > "$f"
}
txt() { node -e 'console.log(JSON.stringify([{type:"text",text:process.argv[1]}]))' "$1"; }
wr()  { node -e 'console.log(JSON.stringify([{type:"tool_use",name:"Write",input:{file_path:process.argv[1],content:process.argv[2]}}]))' "$1" "$2"; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # OS-3
run() { printf '{"transcript_path":"%s","cwd":"%s"}' "$(native "$1")" "$(native "$tmp")" | node "$gate"; }
expect() {   # expect <label> block|pass <output>
  if [ "$2" = block ]; then case "$3" in *'"decision":"block"'*) echo "ok   $1";; *) echo "FAIL $1 (expected block)"; fail=1;; esac
  else case "$3" in *'"decision":"block"'*) echo "FAIL $1 (expected pass)"; fail=1;; *) echo "ok   $1";; esac; fi
}

turn "$tmp/a.jsonl" "why did you not restart?" "$(txt 'Henceforth I keep the watcher running while onPC runs.')" \
  "$(wr "$tmp/docs/maintenance/feedback-protocol.md" 'watcher runs while onPC runs')"
expect "real case: promise carried only by a feedback-protocol entry blocks" block "$(run "$tmp/a.jsonl")"

turn "$tmp/b.jsonl" "x" "$(txt 'From now on I never open a window on the operator machine.')" \
  "$(wr "$tmp/mcp/src/x.md" 'never open a window')"
expect "English promise with only a doc write blocks" block "$(run "$tmp/b.jsonl")"

turn "$tmp/c.jsonl" "x" "$(txt 'From now on I never open a window on the operator machine.')" \
  "$(wr "$tmp/core/helpers/no-window-gate.cjs" '// refuse any command that would open a window on the operator machine')"
expect "promise carried by a gate written this turn passes" pass "$(run "$tmp/c.jsonl")"

turn "$tmp/d.jsonl" "x" "$(txt 'Henceforth we keep the watcher running.')" \
  "$(wr "$tmp/.claude/rules/stop-checks.json" '{"checks":[{"label":"WATCHER keeps running"}]}')"
expect "instance-phrased promise carried by gate data (.claude/rules/*.json) passes" pass "$(run "$tmp/d.jsonl")"

turn "$tmp/e.jsonl" "x" "$(txt 'The detector will report it from now on.')"
expect "negative control: a sentence about a tool is no promise" pass "$(run "$tmp/e.jsonl")"

turn "$tmp/f.jsonl" "x" "$(txt 'The rule says "henceforth I never again", quoted.')"
expect "negative control: a quoted mention is no promise" pass "$(run "$tmp/f.jsonl")"

turn "$tmp/g.jsonl" "old turn" "$(wr "$tmp/core/helpers/no-window-gate.cjs" 'never open a window operator machine')"
printf '{"type":"user","message":{"role":"user","content":"new turn"}}\n{"type":"assistant","message":{"role":"assistant","content":%s}}\n' "$(txt 'From now on I never open a window on the operator machine.')" >> "$tmp/g.jsonl"
expect "a gate written in an EARLIER turn does not carry this turn's promise" block "$(run "$tmp/g.jsonl")"

[ $fail -eq 0 ] && echo "test-commitment-carrier-gate: all passed" || echo "test-commitment-carrier-gate: FAILED"
exit $fail
