#!/usr/bin/env bash
# Fixture test for derived-carry-gate - both directions. The measured case of 2026-11-17 (a conclusion about a port
# came back as a fact two replies later), once with an instance marker given as DATA and once with a built-in, and
# the controls: the repeat keeps its marker, a read carried every anchor in between, the sentence is about something
# else. Usage: bash scripts/test-derived-carry-gate.sh   (exit 0 = all fixtures pass)
set -u
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
G="$ROOT/helpers/derived-carry-gate.cjs"
[ -f "$G" ] || G="$ROOT/core/helpers/derived-carry-gate.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

# The instance's own marker is DATA (the engine keeps English built-ins); "by my reckoning" stands in for it.
mkdir -p "$T/.claude/rules"
printf '%s\n' '{"derived_markers": ["by my reckoning"], "stop_words": ["router"]}' > "$T/.claude/rules/derived-patterns.json"

js()   { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
user() { printf '{"message":{"role":"user","content":%s}}\n' "$(js "$1")"; }
asst() { printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(js "$1")"; }
tool() { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"%s","input":%s}]}}\n' "$1" "$2"; }
check() {  # name file block|allow
  local out
  out="$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$(native "$2")" "$(native "$T")" | node "$G" 2>&1)"
  if [ "$3" = block ]; then case "$out" in *DERIVED-CARRY*) ok "$1 blocks";; *) bad "$1 did not block: '$out'";; esac
  else [ -z "$out" ] && ok "$1 allows" || bad "$1 blocked wrongly: '$out'"; fi
}

E="By my reckoning the node runs on PoE at router ether7, only because it runs and sits nowhere else."
N="At router ether7 the node ran on PoE instead."
f="$T/1.jsonl"; { user "what sits on ether7?"; asst "$E"; user "and now?"; asst "$N"; } > "$f"
check "the measured case: a conclusion comes back as a fact" "$f" block
f="$T/2.jsonl"; { user "what sits on ether7?"; asst "$E"; user "and now?"; asst "At router ether7 the node presumably ran on PoE."; } > "$f"
check "the repeat keeps its marker" "$f" allow
f="$T/3.jsonl"; { user "what sits on ether7?"; asst "$E"; tool mcp__mikrotik__mikrotik_poe '{"device":"router","port":"ether7"}'; user "and now?"; asst "$N"; } > "$f"
check "a read carried every anchor in between" "$f" allow
f="$T/3w.jsonl"; { user "what sits on ether7?"; asst "$E"; tool Edit '{"file_path":"docs/log.md","new_string":"router ether7 PoE"}'; user "and now?"; asst "$N"; } > "$f"
check "a write naming both anchors is no measurement" "$f" block
f="$T/3p.jsonl"; { user "what sits on ether7?"; asst "$E"; tool mcp__x__ports '{"device":"router","port":"ether7"}'; user "and now?"; asst "$N"; } > "$f"
check "a read of the port without PoE does not replace the PoE conclusion" "$f" block
f="$T/4.jsonl"; { user "what sits on ether7?"; asst "$E"; user "and now?"; asst "The switch sw-foh has ether21 in VLAN 30 now."; } > "$f"
check "a sentence about something else" "$f" allow
f="$T/5.jsonl"; { user "status?"; asst "The node probably ran on PoE at ether7, I infer that from the link alone."; user "and now?"; asst "The node ran on PoE at ether7."; } > "$f"
check "a built-in marker, the same repeat" "$f" block
f="$T/6.jsonl"; { user "status?"; asst "The node ran on PoE at ether7."; user "and now?"; asst "The node ran on PoE at ether7."; } > "$f"
check "an earlier sentence without a marker is no source" "$f" allow
f="$T/7.jsonl"; { user "status?"; asst "The node probably ran on PoE at ether7, I infer that from the link alone."; user "and now?"; asst 'I said before: "The node ran on PoE at ether7." - not measured yet.'; } > "$f"
check "a quoted sentence is talk about the claim" "$f" allow

echo
[ "$fail" -eq 0 ] && echo "derived-carry-gate fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
