#!/usr/bin/env bash
# covers: file-guard secret-guard mechanism-guard freshness-gate
#
# Effect proof for the PreToolUse guards. These are the most expensive ones to have
# silently dead: they are the only thing between a routine tool call and an edited
# secret, a leaked credential or a shortcut around a documented process. Presence
# proves nothing — every one of them looks identical whether it fires or not.
#
# Each guard is checked in BOTH directions: an input it MUST block, and one it must
# wave through. A guard that blocks everything is as broken as one that blocks nothing,
# and only the second run tells them apart.
#
# Usage: bash scripts/test-guards.sh   (exit 0 = all fixtures pass)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
fail=0
# file-guard has a branch gate for core checkouts: on a detached HEAD it blocks
# every edit on purpose, and CI checks out exactly that. So every path here lives in
# a throwaway directory — otherwise the fixture measures the checkout, not the guard.
FG="$(mktemp -d)"
trap 'rm -rf "$FG"' EXIT
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

# Two layouts, one fixture: inside a brain the helpers live under core/helpers, inside
# the core repo itself under helpers. A fixture that only knows one of them silently
# tests nothing in the other — so resolution is explicit, and a missing subject is
# SKIPPED loudly rather than passing quietly.
resolve() {
  for cand in "core/$1" "$1"; do
    [ -f "$cand" ] && { printf '%s' "$cand"; return 0; }
  done
  return 1
}
skip() { echo "  --  $1 (not in this layout)"; }


# $1 name, $2 helper, $3 payload, $4 block|allow
probe() {
  local out rc
  local helper
  helper=$(resolve "helpers/$2") || { skip "$1"; return 0; }
  out=$(printf '%s' "$3" | CLAUDE_PROJECT_DIR="$ROOT" node "$helper" 2>&1)
  rc=$?
  # A guard says "no" either by exit code 2 (stderr form) or by a deny/ask decision.
  if [ "$rc" -eq 2 ] || printf '%s' "$out" | grep -q '"permissionDecision": *"\(deny\|ask\)"'; then
    [ "$4" = "block" ] && ok "$1 blocks" || bad "$1 blocked what it should allow: $out"
  else
    [ "$4" = "allow" ] && ok "$1 allows" || bad "$1 did NOT block (rc=$rc): $out"
  fi
}

echo "PreToolUse guards:"

# --- file-guard: secrets are not edited by an agent, ever --------------------
probe "file-guard/.env" file-guard.cjs \
  '{"tool_name":"Edit","tool_input":{"file_path":"'"$FG"'/.env"},"cwd":"'"$FG"'"}' block
probe "file-guard/id_rsa" file-guard.cjs \
  '{"tool_name":"Write","tool_input":{"file_path":"/opt/fixture/.ssh/id_rsa"},"cwd":"'"$FG"'"}' block
probe "file-guard/normal file" file-guard.cjs \
  '{"tool_name":"Edit","tool_input":{"file_path":"'"$FG"'/README.md"},"cwd":"'"$FG"'"}' allow

# --- secret-guard: reading a secret into context is the leak -----------------
probe "secret-guard/read .env" secret-guard.cjs \
  '{"tool_name":"Read","tool_input":{"file_path":"'"$FG"'/.env"},"cwd":"'"$FG"'"}' block
probe "secret-guard/read a doc" secret-guard.cjs \
  '{"tool_name":"Read","tool_input":{"file_path":"'"$FG"'/README.md"},"cwd":"'"$FG"'"}' allow

# --- mechanism-guard: a documented path exists, so the shortcut is refused ---
# The RULES are instance data, so the fixture brings its own instead of depending on
# whatever the surrounding brain happens to carry — otherwise this passes or fails for
# reasons that have nothing to do with the guard.
MG=$(mktemp -d)
mkdir -p "$MG/.claude/rules"
printf '%s' '[{"pattern":"\\bfixture-shortcut\\b","was":"fixture","stattdessen":"the documented path"}]' \
  > "$MG/.claude/rules/mechanism-rules.json"
mg_probe() { # $1 name, $2 command, $3 block|allow
  local out rc
  local helper; helper=$(resolve helpers/mechanism-guard.cjs) || { skip "$1"; return 0; }
  out=$(printf '{"tool_name":"%s","tool_input":{"command":"%s"},"cwd":"%s"}' "${4:-Bash}" "$2" "$MG" \
        | CLAUDE_PROJECT_DIR="$MG" node "$helper" 2>&1)
  rc=$?
  if [ "$rc" -eq 2 ] || printf '%s' "$out" | grep -q '"permissionDecision": *"deny"'; then
    [ "$3" = block ] && ok "$1 blocks" || bad "$1 blocked what it should allow"
  else
    [ "$3" = allow ] && ok "$1 allows" || bad "$1 did NOT block: ${out:0:80}"
  fi
}
mg_probe "mechanism-guard/known shortcut" "fixture-shortcut --now" block
mg_probe "mechanism-guard/plain command" "git status --short" allow
# The marker is the guard's own escape hatch — if it stopped working, every documented
# shortcut would be unreachable and the guard would be switched off within a day.
mg_probe "mechanism-guard/MECHANISM-OK marker" "fixture-shortcut --now  # MECHANISM-OK: proving the escape hatch" allow
# A hand-built watcher is a Monitor command, not a Bash one. The guard never reads
# tool_name, so this proves it is tool-agnostic and the ONLY thing between the class
# and the guard is the matcher in settings.json. That other half is hook-coverage.py,
# which since 2026-09-02 reports a matcher narrower than the template: the presence
# of the hook alone said "covered" while every Monitor command walked past it.
mg_probe "mechanism-guard/Monitor payload" "fixture-shortcut --now" block Monitor
rm -rf "$MG"

# --- freshness-gate: only the Workflow tool concerns it ----------------------
# The blocking case needs a completed expensive run in this session's record, which a
# fixture cannot fake without inventing a run id. What IS provable here: it stays out
# of the way of everything else — the failure mode that would make it deny real work.
probe "freshness-gate/other tool" freshness-gate.cjs \
  '{"tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"'"$FG"'"}' allow
probe "freshness-gate/workflow resume" freshness-gate.cjs \
  '{"tool_name":"Workflow","tool_input":{"resumeFromRunId":"wf_abc123"},"cwd":"'"$FG"'"}' allow

echo
[ "$fail" -eq 0 ] && echo "guard fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
