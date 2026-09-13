#!/usr/bin/env bash
# covers: memory-recall
#
# Both directions. The "must stay silent" half carries the weight: this hook runs on
# EVERY prompt, so a false positive is wallpaper the operator pays for each turn. Cases:
#   1. topic prompt              -> names the matching memory file, nothing else
#   2. filler prompt             -> no output at all
#   3. --record                  -> no output, but a JSONL line with the candidates
#   4. cooldown                  -> same prompt twice in one session, second call empty
#   5. instance config replaces  -> a stopword list that swallows the topic word = silent
#   6. index files never appear  -> MEMORY.md / index-*.md are pointers already
#   7. broken frontmatter        -> skipped, exit 0, the rest still works
#   8. output cap                -> 40 matching files, block stays under 1200 bytes
#   9. CRLF frontmatter          -> a file with \r\n line endings still indexes (OS-2 class)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
# A path that travels INSIDE data (an env var read by a native process) is not translated
# by the shell — on Git Bash node would receive /tmp/... and resolve nothing (OS-3).
native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi
}
resolve() { for c in "core/$1" "$1"; do [ -f "$c" ] && { printf '%s' "$c"; return 0; }; done; return 1; }
HOOK=$(resolve helpers/memory-recall.cjs) || { echo "  --  memory-recall not in this layout"; exit 0; }

MEM="$T/memory"; BRAIN="$T/brain"
mkdir -p "$MEM" "$BRAIN/.claude/rules"
mem() { # $1 file, $2 name, $3 description
  printf -- '---\nname: %s\ndescription: %s\nmetadata:\n  type: project\n---\n\nbody text that must never be read by the hook: SECRET-BODY-MARKER\n' "$2" "$3" > "$MEM/$1"
}
mem rig-vlan-multicast.md rig-vlan-multicast "MikroTik rig: VLAN trunks and IGMP multicast flooding on the CRS switches, measured with the bench"
mem touchosc-pipeline.md touchosc-pipeline "TouchOSC layouts built from a spec, probe proves the OSC address on the phone"
mem release-policy.md release-policy "Core release and marketplace pin are the operator's word, beta channel first"
printf -- '# Memory Index\n\n- [Rig](rig-vlan-multicast.md) — MikroTik VLAN multicast\n' > "$MEM/MEMORY.md"
printf -- '---\nname: index-rig\ndescription: rig sub-index VLAN multicast MikroTik\n---\n- [x](rig-vlan-multicast.md)\n' > "$MEM/index-rig.md"

# $1 name, $2 prompt, $3 session, $4.. extra args; sets OUT and RC
run_hook() {
  local name="$1" prompt="$2" session="$3"; shift 3
  OUT=$(printf '{"session_id":"%s","prompt":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit"}' \
        "$session" "$prompt" "$(native "$BRAIN")" \
      | CLAUDE_MEMORY_DIR="$(native "$MEM")" CLAUDE_PROJECT_DIR="$(native "$BRAIN")" node "$HOOK" "$@" 2>"$T/err")
  RC=$?
}

# 1. topic prompt names the rig file and only the rig file
run_hook c1 "why does multicast flood every VLAN on the MikroTik switch" s1
case "$OUT" in
  *rig-vlan-multicast.md*) case "$OUT" in *touchosc*|*release-policy*) bad "1 topic prompt: unrelated file named";; *) ok "1 topic prompt names the rig file";; esac;;
  *) bad "1 topic prompt: rig file not named (out: ${OUT:0:120})";;
esac
[ "$RC" = 0 ] || bad "1 exit code $RC"
case "$OUT" in *SECRET-BODY-MARKER*) bad "1 body text leaked into the block";; esac
case "$OUT" in *'<memory-recall'*'instructions="never"'*) ok "1 block carries the trust attributes";; *) bad "1 block attributes missing";; esac

# 2. filler prompt stays silent
run_hook c2 "ok, go on with the plan" s2
[ -z "$OUT" ] && ok "2 filler prompt silent" || bad "2 filler prompt produced output: ${OUT:0:120}"

# 3. --record: silent, JSONL line written
run_hook c3 "MikroTik VLAN multicast question" s3 --record
[ -z "$OUT" ] && ok "3 record mode silent" || bad "3 record mode printed: ${OUT:0:120}"
LOG="$BRAIN/.claude-state/memory-recall.jsonl"
logtext=""; [ -f "$LOG" ] && logtext=$(cat "$LOG")
case "$logtext" in *rig-vlan-multicast.md*) ok "3 record line written";; *) bad "3 record line missing";; esac
# the log is always written, also without --record (precision stays measurable after arming)
n_before=$(wc -l < "$LOG" | tr -d ' ')
run_hook c3b "MikroTik VLAN multicast again" s3b
n_after=$(wc -l < "$LOG" | tr -d ' ')
[ "$n_after" -gt "$n_before" ] && ok "3 inject mode also records" || bad "3 inject mode did not record"

# 4. cooldown: same session, same file, second call silent
run_hook c4a "MikroTik VLAN multicast" s4
run_hook c4b "MikroTik VLAN multicast" s4
[ -z "$OUT" ] && ok "4 cooldown silences the repeat" || bad "4 repeat still named: ${OUT:0:120}"

# 5. instance config replaces the defaults: stopwords swallow the topic
printf '{"stopwords":["mikrotik","vlan","multicast","switch","flood"]}\n' > "$BRAIN/.claude/rules/memory-recall.json"
run_hook c5 "why does multicast flood every VLAN on the MikroTik switch" s5
[ -z "$OUT" ] && ok "5 instance stopwords replace defaults" || bad "5 config ignored: ${OUT:0:120}"
rm "$BRAIN/.claude/rules/memory-recall.json"

# 6. a matching TOPIC index is injected whole (its entry lines), MEMORY.md never appears
run_hook c6 "index rig sub-index VLAN multicast MikroTik" s6
case "$OUT" in *'topic index memory/index-rig.md'*'- [x](rig-vlan-multicast.md)'*) ok "6 topic index injected with its entries";; *) bad "6 topic index not injected: ${OUT:0:160}";; esac
case "$OUT" in *MEMORY.md*) bad "6 MEMORY.md named";; esac
run_hook c6b "index rig sub-index VLAN multicast MikroTik" s6
case "$OUT" in *'topic index'*) bad "6 topic injected twice in one session";; *) ok "6 topic once per session";; esac

# 7. broken frontmatter is skipped, the rest still works
printf -- '---\nname: broken\ndescription: MikroTik VLAN\nno closing fence' > "$MEM/broken.md"
printf 'plain file without frontmatter about MikroTik VLAN multicast\n' > "$MEM/plain.md"
run_hook c7 "MikroTik VLAN multicast" s7
[ "$RC" = 0 ] || bad "7 exit code $RC with broken file"
case "$OUT" in *rig-vlan-multicast.md*) ok "7 broken files skipped, good one still named";; *) bad "7 good file lost next to broken ones";; esac
case "$OUT" in *broken.md*|*plain.md*) bad "7 broken/plain file named";; esac
rm "$MEM/broken.md" "$MEM/plain.md"

# 8. output cap (pointer block; the topic index is moved away so only pointers count)
mv "$MEM/index-rig.md" "$T/index-rig.md"
for i in $(seq 1 40); do mem "many-$i.md" "many-$i" "MikroTik VLAN multicast flooding note number $i with a long description that pads the line out to something realistic for an index hook"; done
run_hook c8 "MikroTik VLAN multicast flooding" s8
bytes=$(printf %s "$OUT" | wc -c | tr -d ' ')
[ "$bytes" -le 1300 ] && ok "8 block capped ($bytes bytes)" || bad "8 block too big: $bytes bytes"
rm "$MEM"/many-*.md
mv "$T/index-rig.md" "$MEM/index-rig.md"

# 9. CRLF frontmatter still indexes
printf -- '---\r\nname: crlf-note\r\ndescription: sACN unicast to the Resolume box over the show network\r\nmetadata:\r\n  type: project\r\n---\r\n' > "$MEM/crlf-note.md"
run_hook c9 "sACN unicast Resolume show network" s9
case "$OUT" in *crlf-note.md*) ok "9 CRLF frontmatter parsed";; *) bad "9 CRLF file not found: ${OUT:0:120}";; esac

# 10-13. --tool mode (PreToolUse): a mapped MCP tool or skill injects the topic index once
printf '{"topics":{"index-rig.md":{"tools":["^mcp__mikrotik__"],"skills":["^rig-health-check$"]}}}\n' > "$BRAIN/.claude/rules/memory-recall.json"
run_tool() { # $1 session, $2 tool_name, $3 tool_input json, $4.. extra args
  local session="$1" tool="$2" ti="$3"; shift 3
  OUT=$(printf '{"session_id":"%s","tool_name":"%s","tool_input":%s,"cwd":"%s","hook_event_name":"PreToolUse"}' \
        "$session" "$tool" "$ti" "$(native "$BRAIN")" \
      | CLAUDE_MEMORY_DIR="$(native "$MEM")" CLAUDE_PROJECT_DIR="$(native "$BRAIN")" node "$HOOK" --tool "$@" 2>"$T/err")
  RC=$?
}
run_tool t1 mcp__mikrotik__mikrotik_health '{"device":"router"}'
case "$OUT" in *'"hookEventName":"PreToolUse"'*'"additionalContext"'*'index-rig.md'*'rig-vlan-multicast.md'*) ok "10 mapped MCP tool injects the topic index as PreToolUse JSON";; *) bad "10 tool mode: ${OUT:0:160}";; esac
case "$OUT" in *permissionDecision*) bad "10 tool mode must not decide permissions";; esac
run_tool t1 mcp__mikrotik__mikrotik_health '{"device":"router"}'
[ -z "$OUT" ] && ok "11 topic once per session via tool" || bad "11 injected twice: ${OUT:0:120}"
run_tool t2 Bash '{"command":"ls"}'
[ -z "$OUT" ] && ok "12 unmapped tool silent" || bad "12 unmapped tool produced: ${OUT:0:120}"
run_tool t3 Skill '{"skill":"rig-health-check"}'
case "$OUT" in *index-rig.md*) ok "13 mapped skill injects";; *) bad "13 skill not matched: ${OUT:0:120}";; esac
run_tool t4 Skill '{"skill":"rig-health-check"}' --record
[ -z "$OUT" ] && ok "13 tool mode honours --record" || bad "13 record mode printed"
# the prompt path shares the once-per-session state with the tool path
run_hook c13 "MikroTik VLAN multicast" t3
case "$OUT" in *'topic index'*) bad "13 topic re-injected by prompt after tool";; *) ok "13 prompt path sees the tool path's state";; esac
rm "$BRAIN/.claude/rules/memory-recall.json"

# 14-18. SHARED memory at tool time (2026-09-13): the same trigger injects the shared
# record's topic INDEX, freshness-filtered by the dates the generator stamps per line.
# Both directions again: the fresh lines must come, the stale line must not, and a
# brain without a shared repo must see nothing at all.
SHARED="$T/shared"; mkdir -p "$SHARED/grandma3"
TODAY=$(date -u +%F)
printf -- '# grandma3 — index\n\n- [fresh one](../grandma3/fresh-one.md) — recent · for: x · %s\n- [old one](../grandma3/old-one.md) — ancient · ~2026-01-01\n- [fresh two](../grandma3/fresh-two.md) — also recent · ~%s\n' "$TODAY" "$TODAY" > "$SHARED/grandma3/INDEX.md"
printf '{"sharedTopics":{"grandma3":{"tools":["^mcp__grandma3__"]}},"sharedDays":14}\n' > "$BRAIN/.claude/rules/memory-recall.json"
run_shared() { # $1 session, $2 tool, $3 repo path (may be missing), $4.. extra
  local session="$1" tool="$2" repo="$3"; shift 3
  OUT=$(printf '{"session_id":"%s","tool_name":"%s","tool_input":{},"cwd":"%s","hook_event_name":"PreToolUse"}' \
        "$session" "$tool" "$(native "$BRAIN")" \
      | SHARED_MEMORY_REPO="$(native "$repo")" CLAUDE_MEMORY_DIR="$(native "$MEM")" CLAUDE_PROJECT_DIR="$(native "$BRAIN")" node "$HOOK" --tool "$@" 2>"$T/err")
  RC=$?
}
run_shared sh1 mcp__grandma3__gma3_info "$SHARED"
case "$OUT" in *'shared-memory grandma3'*'2 of 3 entries dated since'*'fresh one'*'fresh two'*) ok "14 mapped tool injects the shared topic index, fresh lines only";; *) bad "14 shared index not injected: ${OUT:0:200}";; esac
case "$OUT" in *'old one'*) bad "14 stale line leaked past the freshness cutoff";; *) ok "14 stale line filtered";; esac
[ "$RC" = 0 ] || bad "14 exit code $RC"
run_shared sh1 mcp__grandma3__gma3_info "$SHARED"
[ -z "$OUT" ] && ok "15 shared topic once per session" || bad "15 shared injected twice: ${OUT:0:120}"
run_shared sh2 mcp__grandma3__gma3_info "$T/nowhere"
[ -z "$OUT" ] && [ "$RC" = 0 ] && ok "16 no shared repo: silent, exit 0" || bad "16 missing repo produced output or rc=$RC: ${OUT:0:120}"
printf -- '# grandma3 — index\n\n- [undated a](../grandma3/a.md) — no date at all\n- [undated b](../grandma3/b.md) — none here either\n' > "$SHARED/grandma3/INDEX.md"
run_shared sh3 mcp__grandma3__gma3_info "$SHARED"
case "$OUT" in *'2 entries, none dated'*'undated a'*'undated b'*) ok "17 an undated index is shown whole, and says so";; *) bad "17 undated index mishandled: ${OUT:0:200}";; esac
run_shared sh4 mcp__grandma3__gma3_info "$SHARED" --record
[ -z "$OUT" ] && ok "18 shared path honours --record" || bad "18 record mode printed"
logtext=$(cat "$BRAIN/.claude-state/memory-recall.jsonl")
case "$logtext" in *'"shared":[{"topic":"grandma3"'*) ok "18 record line carries the shared tally";; *) bad "18 record line lacks the shared tally";; esac
rm "$BRAIN/.claude/rules/memory-recall.json"

[ $fail = 0 ] && echo "test-memory-recall: all green" || echo "test-memory-recall: FAILURES"
exit $fail
