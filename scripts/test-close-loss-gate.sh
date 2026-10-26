#!/usr/bin/env bash
# covers: close-loss-gate
# Fixtures for helpers/close-loss-gate.cjs - both directions. The must-block cases are the incident
# (2026-10-26, Windows instance): a release in the first sentence, a command only the operator could
# run further down, pointing into the session scratchpad; plus unpushed commits under a release.
# Usage: bash scripts/test-close-loss-gate.sh   (exit 0 = pass)
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
gate="$here/../helpers/close-loss-gate.cjs"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # OS-3
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
turn() { # turn <file> <reply text>
  { printf '{"type":"user","message":{"role":"user","content":"close the session"}}\n'
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(js "$2")"; } > "$1"
}
run() { printf '{"transcript_path":"%s","cwd":"%s"}' "$(native "$1")" "$(native "$2")" | SHARED_MEMORY_REPO="${SM:-$T/none}" HOME="$T/home" USERPROFILE="$T/home" node "$(native "$gate")"; }
expect() { # expect <label> block|allow <output>
  case "$3" in
    *'"decision":"block"'*) [ "$2" = block ] && echo "  OK  $1" || { echo "  FAIL $1 (blocked: ${3:0:160})"; fail=1; } ;;
    *) [ "$2" = allow ] && echo "  OK  $1" || { echo "  FAIL $1 (did not block)"; fail=1; } ;;
  esac
}

# a repo with an upstream: clean, then one local commit not pushed
git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/repo" 2>/dev/null
git -C "$T/repo" -c user.email=t@example.org -c user.name=t commit -q --allow-empty -m base
git -C "$T/repo" push -q origin HEAD 2>/dev/null
git -C "$T/repo" branch -q --set-upstream-to=origin/"$(git -C "$T/repo" branch --show-current)" 2>/dev/null
C="$T/repo"

turn "$T/1.jsonl" "Everything persisted - you can shut down."
expect "clean release, nothing open" allow "$(run "$T/1.jsonl" "$C")"

turn "$T/2.jsonl" "Persisted - you can shut down.
- notes written
- run this yourself:
! gh auth refresh -s workflow"
expect "the incident: release first, a ! command for the operator below" block "$(run "$T/2.jsonl" "$C")"

turn "$T/3.jsonl" "Done - you can shut down. The patch is at /private/tmp/claude-501/x/abc/scratchpad/fix.patch"
expect "release with a file inside the session scratchpad" block "$(run "$T/3.jsonl" "$C")"

git -C "$C" -c user.email=t@example.org -c user.name=t commit -q --allow-empty -m local
turn "$T/4.jsonl" "All done, you can shut down now."
expect "release with an unpushed commit" block "$(run "$T/4.jsonl" "$C")"

turn "$T/5.jsonl" "Working on it; the commit goes up after the CI run."
expect "no release, unpushed commit (control)" allow "$(run "$T/5.jsonl" "$C")"

mkdir -p "$C/.claude/rules"
printf '%s\n' '{"release_patterns":["\\bdu kannst runterfahren\\b"],"hand_patterns":["\\bhandgriff\\b"]}' > "$C/.claude/rules/close-loss.json"
git -C "$C" push -q origin HEAD 2>/dev/null
turn "$T/6.jsonl" "Gespeichert, du kannst runterfahren. Offen: ein Handgriff am Router."
expect "instance release and hand-step words (operator's language as data)" block "$(run "$T/6.jsonl" "$C")"
turn "$T/7.jsonl" "Gespeichert, du kannst runterfahren."
expect "instance release, nothing open (control)" allow "$(run "$T/7.jsonl" "$C")"

# Neighbor repos (class search after #149): the shared-memory repo and the instance's `repos` list.
git init -q --bare "$T/sm-origin.git"
git clone -q "$T/sm-origin.git" "$T/sm" 2>/dev/null
git -C "$T/sm" -c user.email=t@example.org -c user.name=t commit -q --allow-empty -m base
git -C "$T/sm" push -q origin HEAD 2>/dev/null
git -C "$T/sm" branch -q --set-upstream-to=origin/"$(git -C "$T/sm" branch --show-current)" 2>/dev/null
git -C "$T/sm" -c user.email=t@example.org -c user.name=t commit -q --allow-empty -m entry
turn "$T/8.jsonl" "Gespeichert, du kannst runterfahren."
SM="$T/sm" expect "release while the shared-memory repo has an unpushed entry" block "$(SM="$T/sm" run "$T/8.jsonl" "$C")"
printf '%s\n' '{"release_patterns":["\\bdu kannst runterfahren\\b"],"repos":["'"$(native "$T/sm")"'"]}' > "$C/.claude/rules/close-loss.json"
expect "release while a repo of the instance list has an unpushed commit" block "$(run "$T/8.jsonl" "$C")"
git -C "$T/sm" push -q origin HEAD 2>/dev/null
expect "the same after the push (control)" allow "$(SM="$T/sm" run "$T/8.jsonl" "$C")"
[ "$fail" = 0 ] && echo "close-loss-gate: all cases pass" || { echo "close-loss-gate: FAILURES"; exit 1; }
