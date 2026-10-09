#!/usr/bin/env bash
# covers: live-read-gate
#
# Fixture test for helpers/live-read-gate.cjs — both directions. A gate nobody has seen
# FIRE is as useless as one nobody has seen STAY SILENT, so every domain rule gets a
# blocking case and an allowing case, plus the partial-read edges.
#
# Negative control: every must-block case is ALSO run against an always-allow stub and
# must come back "allow" there — proof that the case discriminates instead of passing
# for a reason unrelated to the gate. The stub is built in the temp dir; an alternative
# engine can be passed as $1 to run the whole suite against it.
#
# Usage: bash scripts/test-live-read-gate.sh [gate.cjs]   (exit 0 = all fixtures pass)
set -u

# Paths travel INSIDE data here (the transcript JSON, the cwd/project dir, the required
# paths in the instance file, the cat command the gate resolves). Git Bash /tmp/... does
# not resolve for node — every must-block case would read nothing and every must-allow
# case would pass for the wrong reason (docs/os-traps.md OS-3). cygpath states the path
# natively; elsewhere a no-op.
native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
resolve() { for c in "core/$1" "$1"; do [ -f "$ROOT/$c" ] && { printf '%s' "$ROOT/$c"; return 0; }; done; return 1; }
if [ $# -ge 1 ]; then GATE="$1"; else
  GATE=$(resolve helpers/live-read-gate.cjs) || { echo "  --  live-read-gate not in this layout"; exit 0; }
fi
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
NT=$(native "$T")
fail=0
must_block=0
flipped=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

STUB="$T/always-allow.cjs"
printf '%s\n' "process.stdin.resume(); process.stdin.on('end', () => process.exit(0));" > "$STUB"

mkdir -p "$T/.claude/rules" "$T/docs/net" "$T/.claude-state"
printf 'ledger\n' > "$T/docs/net/ledger.md"
printf 'memo\n' > "$T/memo.md"
# a LONG required file: 1468 lines, far beyond what one Read delivers
seq 1 1468 | sed 's/^/line /' > "$T/docs/net/long.md"
# Two domains. The second required path of the first is ABSOLUTE (an instance keeps some
# mandatory reading outside the repo, e.g. in its auto-memory). Addresses are RFC 5737.
CFG='{"domains":[
 {"name":"net","tools":["^mcp__nettool__"],
  "bash":["(?:^|[;&|(]\\s*)(?:\\S*/)?(ping|nc|ssh)\\b[^\\n;&|]*\\b192\\.0\\.2\\.\\d+\\b","(?:^|[;&|(]\\s*)(?:bash\\s+)?(?:\\S*/)?net-ssh(\\.sh)?(\\s|$)"],
  "required":[{"path":"docs/net/ledger.md","label":"first"},{"path":"MEMO","label":"second"}]},
 {"name":"long","tools":["^mcp__longtool__"],"bash":[],
  "required":[{"path":"docs/net/long.md","label":"the long one"}]}
]}'
printf '%s\n' "${CFG//MEMO/$NT/memo.md}" > "$T/.claude/rules/live-read.json"

# transcript builders
#   line: one assistant message with one tool_use block (the CALL)
#   res : the harness's record of what a Read DELIVERED (file, startLine, numLines, totalLines)
line() { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"%s","input":%s}]}}\n' "$1" "$2"; }
res()  { printf '{"message":{"role":"user","content":[{"type":"tool_result","content":"x"}]},"toolUseResult":{"type":"text","file":{"filePath":"%s","startLine":%s,"numLines":%s,"totalLines":%s}}}\n' "$NT/$1" "$2" "$3" "$4"; }
raw() { # $1 engine, $2 transcript, $3 tool name, $4 tool_input json → the hook's stdout
  printf '{"tool_name":"%s","tool_input":%s,"transcript_path":"%s","cwd":"%s"}' "$3" "$4" "$(native "$2")" "$NT" \
    | CLAUDE_PROJECT_DIR="$NT" node "$1"
}
verdict() { if printf '%s' "$(raw "$@")" | grep -q '"permissionDecision":"deny"'; then echo deny; else echo allow; fi; }
# check <name> <deny|allow> <transcript> <tool> <tool_input>
check() {
  local name="$1" want="$2"; shift 2
  local got; got=$(verdict "$GATE" "$@")
  [ "$got" = "$want" ] && ok "$name → $want" || bad "$name: expected $want, got $got"
  if [ "$want" = deny ]; then
    must_block=$((must_block + 1))
    [ "$(verdict "$STUB" "$@")" = allow ] && flipped=$((flipped + 1))
  fi
}

echo "live-read-gate:"
# 1. nothing read → MCP live tool denied
: > "$T/t1.jsonl"
check "1 MCP live tool, nothing read" deny "$T/t1.jsonl" mcp__nettool__health '{}'

# 2. both required read completely (delivered Read + cat of a small file) → allowed
{ line Read "{\"file_path\":\"$NT/docs/net/ledger.md\"}"; res docs/net/ledger.md 1 1 1; line Bash "{\"command\":\"cat $NT/memo.md\"}"; } > "$T/t2.jsonl"
check "2 both read (Read + cat)" allow "$T/t2.jsonl" mcp__nettool__health '{}'

# 2b. the CALL alone is not a read: a Read tool_use with no delivered record
{ line Read "{\"file_path\":\"$NT/docs/net/ledger.md\"}"; line Bash "{\"command\":\"cat $NT/memo.md\"}"; } > "$T/t2b.jsonl"
check "2b Read call without a delivered result" deny "$T/t2b.jsonl" mcp__nettool__health '{}'

# 3. only ONE of two read → still denied
{ res docs/net/ledger.md 1 1 1; } > "$T/t3.jsonl"
check "3 one of two required files read" deny "$T/t3.jsonl" mcp__nettool__health '{}'

# 4. a window that does not start at line 1 leaves a gap
{ res docs/net/long.md 40 1429 1468; } > "$T/t4.jsonl"
check "4 window from line 40 only" deny "$T/t4.jsonl" mcp__longtool__x '{}'

# 5. grep/sed of the file is not a read either
{ line Bash "{\"command\":\"grep -n foo $NT/docs/net/ledger.md\"}"; line Bash "{\"command\":\"sed -n 1,20p $NT/memo.md\"}"; } > "$T/t5.jsonl"
check "5 grep/sed only" deny "$T/t5.jsonl" mcp__nettool__health '{}'

# 6. Bash network probe at a configured address, nothing read
check "6 ping a configured address, nothing read" deny "$T/t1.jsonl" Bash '{"command":"ping -c 1 192.0.2.249"}'

# 7. Bash that merely MENTIONS the address in a grep: reading, not touching
check "7 grep for an address in docs" allow "$T/t1.jsonl" Bash '{"command":"grep -rn 192.0.2.249 docs/"}'

# 8. configured script → deny without read, allow after
check "8a net-ssh, nothing read" deny "$T/t1.jsonl" Bash '{"command":"scripts/net-ssh.sh router /system resource print"}'
check "8b net-ssh after reading" allow "$T/t2.jsonl" Bash '{"command":"scripts/net-ssh.sh router /system resource print"}'
# 8c. the words in PROSE (a commit message) are not a touch — measured on the proving
#     instance: the first config blocked the commit that documented the gate
check "8c words inside a commit message" allow "$T/t1.jsonl" Bash '{"command":"git commit -m \"docs: net-ssh and ping 192.0.2.1 explained\""}'
# 8d. script after a separator or via bash still counts
check "8d net-ssh after ; via bash" deny "$T/t1.jsonl" Bash '{"command":"cd /x; bash scripts/net-ssh.sh router /export"}'

# 9. unrelated tools are never touched
check "9a unrelated built-in tool" allow "$T/t1.jsonl" Read '{"file_path":"/etc/hosts"}'
check "9b unrelated MCP tool" allow "$T/t1.jsonl" mcp__othertool__status '{}'

# --- the long-file class (coherence scan 2026-09-18 on the proving instance) ----------
# 11. THE measured case: one Read without offset, the harness delivers lines 1-426 of 1468
{ line Read "{\"file_path\":\"$NT/docs/net/long.md\"}"; res docs/net/long.md 1 426 1468; } > "$T/t11.jsonl"
check "11 capped read 1-426 of 1468" deny "$T/t11.jsonl" mcp__longtool__x '{}'
raw "$GATE" "$T/t11.jsonl" mcp__longtool__x '{}' | grep -q 'offset=427' \
  && ok "11b the message says where to continue (offset=427)" || bad "11b expected the continuation offset"

# 12. paging through until every line is covered (overlap allowed)
{ res docs/net/long.md 1 426 1468; res docs/net/long.md 427 500 1468; res docs/net/long.md 900 569 1468; } > "$T/t12.jsonl"
check "12 paged windows covering 1-1468" allow "$T/t12.jsonl" mcp__longtool__x '{}'

# 13. a hole in the middle
{ res docs/net/long.md 1 426 1468; res docs/net/long.md 600 869 1468; } > "$T/t13.jsonl"
check "13 hole 427-599" deny "$T/t13.jsonl" mcp__longtool__x '{}'

# 14. cat of a file too big for untruncated Bash output does not count
{ line Bash "{\"command\":\"cat $NT/docs/net/long.md\"}"; } > "$T/t14.jsonl"
seq 1 6000 | sed 's/^/a long line of filler text /' > "$T/docs/net/long.md"
check "14 cat of a file above the Bash output cap" deny "$T/t14.jsonl" mcp__longtool__x '{}'
seq 1 1468 | sed 's/^/line /' > "$T/docs/net/long.md"

# 15. the file GREW after it was read: the new lines were never delivered
printf 'a new gotcha\nand another\n' >> "$T/docs/net/long.md"
check "15 file grew after the read" deny "$T/t12.jsonl" mcp__longtool__x '{}'
seq 1 1468 | sed 's/^/line /' > "$T/docs/net/long.md"

# 16. a read far back in a large transcript still counts (a 16 MB tail window lost it)
{ res docs/net/ledger.md 1 1 1; line Bash "{\"command\":\"cat $NT/memo.md\"}"; } > "$T/t16.jsonl"
node -e 'const fs=require("fs");const pad=JSON.stringify({message:{role:"user",content:[{type:"tool_result",content:"x".repeat(1024*1024)}]}})+"\n";for(let i=0;i<18;i++)fs.appendFileSync(process.argv[1],pad)' "$NT/t16.jsonl"
check "16 read 18 MB back in the transcript" allow "$T/t16.jsonl" mcp__nettool__health '{}'

# 10. broken instance file → fail-open, logged
printf '{"domains": [' > "$T/.claude/rules/live-read.json"
check "10a broken instance file (fail-open)" allow "$T/t1.jsonl" mcp__nettool__health '{}'
grep -q BAD-CONFIG "$T/.claude-state/live-read-gate.log" 2>/dev/null \
  && ok "10b broken file is logged" || bad "10b expected a BAD-CONFIG log line"
# 10c. no instance file at all → silent no-op: allowed, nothing written
rm -f "$T/.claude/rules/live-read.json" "$T/.claude-state/live-read-gate.log"
check "10c no instance file (inert)" allow "$T/t1.jsonl" mcp__nettool__health '{}'
[ ! -e "$T/.claude-state/live-read-gate.log" ] && ok "10d no instance file writes no log" || bad "10d inert gate wrote a log"

# --- negative control: the always-allow stub must turn every must-block case red ----
if [ "$must_block" -gt 0 ] && [ "$flipped" -eq "$must_block" ]; then
  ok "negative control: always-allow stub fails all $must_block must-block cases"
else
  bad "negative control: only $flipped of $must_block must-block cases discriminate"
fi

echo
[ "$fail" -eq 0 ] && echo "live-read-gate fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
