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

# 2026-10-28: the WRITE is the promise. A rule written straight into memory with a reply that has no future
# word passed (operator: "a note … is not enough, we need mechanically binding ways of working").
ed() { node -e 'console.log(JSON.stringify([{type:"tool_use",name:"Edit",input:{file_path:process.argv[1],old_string:process.argv[2],new_string:process.argv[3]}}]))' "$1" "$2" "$3"; }
mem="$tmp/.claude/projects/p/memory"
printf '{"patterns":["\\\\bhenceforth\\\\b"],"first_person":["\\\\b(I|we)\\\\b"],"rule_words":["\\\\bforbidden\\\\b"],"carrier_words":["Held by"]}\n' > "$tmp/.claude/rules/commitments.json"
turn "$tmp/h.jsonl" "why must I flash?" "$(txt 'I add the rule there.')" \
  "$(wr "$mem/bench-flash.md" 'Who flashes: the AI, never a command block for the operator.')"
expect "real case: a rule written into memory, no mechanism this turn, blocks" block "$(run "$tmp/h.jsonl")"
mkdir -p "$tmp/core/helpers"; printf '// gate\n' > "$tmp/core/helpers/flash-gate.cjs"
turn "$tmp/i.jsonl" "x" "$(wr "$mem/bench-flash.md" 'Never hand over the flash command. Carrier: core/helpers/flash-gate.cjs')"
expect "a written rule naming an EXISTING mechanism file as its carrier passes" pass "$(run "$tmp/i.jsonl")"
turn "$tmp/j.jsonl" "x" "$(wr "$mem/bench-flash.md" 'Never hand over the flash command. Carrier: core/helpers/missing-gate.cjs')"
expect "a carrier line naming a file that does not exist blocks" block "$(run "$tmp/j.jsonl")"
turn "$tmp/k.jsonl" "x" "$(wr "$mem/bench-flash.md" 'Never hand over the flash command.')" \
  "$(wr "$tmp/core/helpers/flash-gate.cjs" '// refuse the flash command block')"
expect "a rule written together with a mechanism in the same turn passes" pass "$(run "$tmp/k.jsonl")"
turn "$tmp/l.jsonl" "x" "$(wr "$mem/MEMORY.md" '- [Bench flash](bench-flash.md) - never by the operator')"
expect "the memory index (one pointer line) is exempt" pass "$(run "$tmp/l.jsonl")"
turn "$tmp/m.jsonl" "x" "$(ed "$mem/bench-flash.md" 'Never hand over the flash command.' $'Never hand over the flash command.\nMeasured on the bench, 2026-10-28.')"
expect "an Edit that only repeats an old rule line as context passes" pass "$(run "$tmp/m.jsonl")"
turn "$tmp/n.jsonl" "x" "$(wr "$tmp/AGENTS.md" 'Flashing by hand is forbidden for the operator.')"
expect "instance rule word (data) in a prose file blocks" block "$(run "$tmp/n.jsonl")"
turn "$tmp/o.jsonl" "x" "$(wr "$tmp/AGENTS.md" 'Flashing by hand is forbidden. Held by: core/helpers/flash-gate.cjs')"
expect "instance carrier word (data) naming an existing mechanism passes" pass "$(run "$tmp/o.jsonl")"

# 2026-10-28: a later text that takes the promise back clears it (the block message names that way out;
# without this the earlier sentence blocked every stop again)
turn "$tmp/p.jsonl" "x" "$(txt 'From now on I never open a window on the operator machine.')" "$(txt 'I take that back: it is not guaranteed until the gate is pinned.')"
expect "a promise taken back in a later text of the same turn passes" pass "$(run "$tmp/p.jsonl")"
turn "$tmp/q.jsonl" "x" "$(txt 'I take that back.')" "$(txt 'From now on I never open a window on the operator machine.')"
expect "a promise made AFTER a retraction still blocks" block "$(run "$tmp/q.jsonl")"

[ $fail -eq 0 ] && echo "test-commitment-carrier-gate: all passed" || echo "test-commitment-carrier-gate: FAILED"
exit $fail
