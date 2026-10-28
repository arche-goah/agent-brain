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
        | HOME="$MG" USERPROFILE="$(if command -v cygpath >/dev/null 2>&1; then cygpath -m "$MG"; else printf '%s' "$MG"; fi)" \
          CLAUDE_PROJECT_DIR="$MG" node "$helper" 2>&1)
  rc=$?
  # HOME/USERPROFILE: the guard also loads the rules of every plugin enabled in ~/.claude. Without
  # them a machine with the core plugin enabled ran these fixture cases against the core's own
  # rules too and went red where CI (no plugins) was green (measured 2026-10-28, macOS).
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
# HEREDOC: the body is data or code depending on its CONSUMER, and the guard must judge
# only what the command EXECUTES. Both directions, because a blanket strip passes the
# first probe and silently turns the guard off for the second — measured 2026-09-12:
# 7 of 8 executed heredoc shapes went blind.
mg_probe "mechanism-guard/heredoc quoted as prose" \
  'git commit -m \"$(cat <<EOF\nnote: fixture-shortcut is banned\nEOF\n)\"' allow
mg_probe "mechanism-guard/heredoc written to a file" \
  'cat <<EOF > doc.md\nfixture-shortcut is banned\nEOF' allow
mg_probe "mechanism-guard/heredoc fed to bash" \
  'bash <<EOF\nfixture-shortcut --now\nEOF' block
mg_probe "mechanism-guard/heredoc fed to ssh" \
  'ssh host <<EOF\nfixture-shortcut --now\nEOF' block
mg_probe "mechanism-guard/heredoc through eval" \
  'eval \"$(cat <<EOF\nfixture-shortcut --now\nEOF\n)\"' block
# MESSAGE TEXT: a commit message or PR body that NAMES a guarded command does not run it —
# measured 2026-10-16, a multi-line commit message with a line starting with a guarded command
# was refused. Both directions again: the message is cut, the command around it is not, and a
# double-quoted message that substitutes a command still runs that command.
mg_probe "mechanism-guard/commit message mentions it (multi-line)" \
  'git commit -m \"fix: guard\nfixture-shortcut is documented\"' allow
mg_probe "mechanism-guard/commit message mentions it (single quotes)" \
  "git commit -m 'fixture-shortcut is documented'" allow
mg_probe "mechanism-guard/PR body mentions it" \
  'gh pr create --title \"x\" --body=\"fixture-shortcut is banned\"' allow
mg_probe "mechanism-guard/command after a message" \
  'git commit -m \"ok\" && fixture-shortcut --now' block
mg_probe "mechanism-guard/message substitutes the command" \
  'git commit -m \"$(fixture-shortcut --now)\"' block
mg_probe "mechanism-guard/message flag on the shortcut itself" \
  'fixture-shortcut -m \"x\"' block
# The shared extraction (published-text.cjs, 2026-10-19) blanks every published value, not only
# the -m/--body forms: a gh api field and an attached -m<text> mention it, they do not run it.
mg_probe "mechanism-guard/gh api field mentions it" \
  'gh api repos/o/r/issues/1/comments -f body=\"fixture-shortcut is banned\"' allow
mg_probe "mechanism-guard/attached -m<text> mentions it" \
  "git commit '-mfixture-shortcut is documented'" allow
mg_probe "mechanism-guard/the shortcut in a later command still blocks" \
  'gh pr comment 1 --body \"ok\"; fixture-shortcut --now' block
rm -rf "$MG"

# --- mechanism-guard: a rule may demand the OPERATOR'S WORD behind the marker ----------
# Incident 2026-09-12: two merges in a shared repo carried the marker with a verbatim operator
# quote that stands in no transcript of that day — an unspecific order smoothed into a crisp
# permission while writing the marker. A rule with `needs_operator_word: true` opens only when
# the justification carries something checkable: a quotation PLUS its date, or a pointer to a
# record file that exists. Every shape is probed in both directions, and the unflagged rule
# next to it is the control that today's behaviour did not move.
# The temp dir crosses into node as DATA (CLAUDE_PROJECT_DIR, and the pointer probes resolve
# files under it), so it is stated natively — OS-3 in docs/os-traps.md.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
MG="$(native "$(mktemp -d)")"
mkdir -p "$MG/.claude/rules" "$MG/docs"
printf '%s' '[{"pattern":"\\bfixture-shortcut\\b","was":"fixture","stattdessen":"the documented path"},{"pattern":"\\bfixture-operator-gate\\b","was":"gated fixture","stattdessen":"agree it with the operator first","needs_operator_word":true}]' \
  > "$MG/.claude/rules/mechanism-rules.json"
printf 'decision: fixture\nrecorded 2026-10-12\n' > "$MG/docs/decision.md"
printf '#!/bin/sh\n' > "$MG/docs/decision.sh"
mg_probe "mechanism-guard/operator word: no marker" "fixture-operator-gate --now" block
mg_probe "mechanism-guard/operator word: bare marker" \
  "fixture-operator-gate --now  # MECHANISM-OK: the operator agreed" block
mg_probe "mechanism-guard/operator word: quote without date" \
  'fixture-operator-gate --now  # MECHANISM-OK: operator: \"go ahead with the gate\"' block
mg_probe "mechanism-guard/operator word: date without quote" \
  "fixture-operator-gate --now  # MECHANISM-OK: agreed on 2026-10-12" block
mg_probe "mechanism-guard/operator word: empty quote + date" \
  'fixture-operator-gate --now  # MECHANISM-OK: operator 2026-10-12: \"\"' block
mg_probe "mechanism-guard/operator word: quote + date" \
  'fixture-operator-gate --now  # MECHANISM-OK: operator 2026-10-12: \"go ahead with the gate\"' allow
mg_probe "mechanism-guard/operator word: low-9 quotes + date" \
  'fixture-operator-gate --now  # MECHANISM-OK: operator 2026-10-12: „go ahead with the gate“' allow
mg_probe "mechanism-guard/operator word: pointer to an existing record" \
  "fixture-operator-gate --now  # MECHANISM-OK: decided, see docs/decision.md:2" allow
mg_probe "mechanism-guard/operator word: pointer beyond the file's end" \
  "fixture-operator-gate --now  # MECHANISM-OK: see docs/decision.md:40" block
mg_probe "mechanism-guard/operator word: pointer to a missing file" \
  "fixture-operator-gate --now  # MECHANISM-OK: see docs/nothing.md" block
mg_probe "mechanism-guard/operator word: pointer to a script is no record" \
  "fixture-operator-gate --now  # MECHANISM-OK: see docs/decision.sh" block
# Controls: the unflagged rule next to a flagged one keeps today's behaviour, in both directions.
mg_probe "mechanism-guard/operator word: unflagged rule + bare marker (control)" \
  "fixture-shortcut --now  # MECHANISM-OK: proving the escape hatch" allow
mg_probe "mechanism-guard/operator word: unflagged rule without marker (control)" \
  "fixture-shortcut --now" block
mg_probe "mechanism-guard/operator word: plain command (control)" "git status --short" allow
rm -rf "$MG"

# --- mechanism-guard: TOOL rules — a tool declares its own internals ------------------
# Incident 2026-10-11: a session on a second machine could not take the defined path and
# built its own client, wrote probes into the tool's IPC file and drove the GUI. The guard
# only knew instance rules. A tool now ships `mechanism-rules.json` at its root, and the
# guard finds it on BOTH ways a tool arrives: a clone referenced in .mcp.json, and an
# enabled plugin. Each way gets a block AND an allow, and a disabled plugin must stay out.
TR=$(mktemp -d)
mkdir -p "$TR/suite/mcp/src" "$TR/proj/.claude" "$TR/fakeuser/.claude/plugins" \
         "$TR/fakeuser/plug-on" "$TR/fakeuser/plug-off"
: > "$TR/suite/mcp/src/index.ts"
printf '%s' '{"tool":"fixture-suite","rules":[{"pattern":"fixture-ipc\\.txt$","target":"path","was":"ipc","instead":"the MCP tools"},{"pattern":"\\bfixture-server-by-hand\\b","was":"server by hand","instead":"the MCP server"}]}' \
  > "$TR/suite/mechanism-rules.json"
printf '{"mcpServers":{"fx":{"command":"node","args":["%s"]}}}' "$(native "$TR/suite/mcp/src/index.ts")" \
  > "$TR/proj/.mcp.json"
printf '%s' '{"tool":"fixture-plugin","rules":[{"pattern":"\\bfixture-plugin-internal\\b","was":"plugin internal","instead":"its MCP tools"}]}' \
  > "$TR/fakeuser/plug-on/mechanism-rules.json"
printf '%s' '{"tool":"fixture-off","rules":[{"pattern":"\\bfixture-disabled-internal\\b","was":"x","instead":"y"}]}' \
  > "$TR/fakeuser/plug-off/mechanism-rules.json"
printf '{"version":2,"plugins":{"on@fx":[{"installPath":"%s"}],"off@fx":[{"installPath":"%s"}]}}' \
  "$(native "$TR/fakeuser/plug-on")" "$(native "$TR/fakeuser/plug-off")" > "$TR/fakeuser/.claude/plugins/installed_plugins.json"
printf '%s' '{"enabledPlugins":{"on@fx":true,"off@fx":false}}' > "$TR/fakeuser/.claude/settings.json"
tr_probe() { # $1 name, $2 tool_name, $3 field (command|file_path), $4 value, $5 block|allow
  local out helper
  helper=$(resolve helpers/mechanism-guard.cjs) || { skip "$1"; return 0; }
  out=$(printf '{"tool_name":"%s","tool_input":{"%s":"%s"}}' "$2" "$3" "$4" \
        | CLAUDE_PROJECT_DIR="$(native "$TR/proj")" HOME="$TR/fakeuser" USERPROFILE="$(native "$TR/fakeuser")" node "$helper" 2>&1)
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then
    [ "$5" = block ] && ok "$1 blocks" || bad "$1 blocked what it should allow"
  else
    [ "$5" = allow ] && ok "$1 allows" || bad "$1 did NOT block: ${out:0:80}"
  fi
}
tr_probe "mechanism-guard/tool rule via .mcp.json clone (command)" Bash command "fixture-server-by-hand --x" block
tr_probe "mechanism-guard/tool rule via clone (path, Write)" Write file_path "$(native "$TR")/x/fixture-ipc.txt" block
tr_probe "mechanism-guard/tool rule via clone (path, Edit)" Edit file_path "$(native "$TR")/x/fixture-ipc.txt" block
tr_probe "mechanism-guard/path rule ignores commands" Bash command "cat notes-about-fixture-ipc.txt.md" allow
tr_probe "mechanism-guard/ordinary Write" Write file_path "$(native "$TR")/x/readme.md" allow
tr_probe "mechanism-guard/tool rule via enabled plugin" Bash command "fixture-plugin-internal now" block
tr_probe "mechanism-guard/disabled plugin stays out" Bash command "fixture-disabled-internal now" allow
tr_probe "mechanism-guard/tool rule + MECHANISM-OK marker" Bash command "fixture-server-by-hand  # MECHANISM-OK: developing the tool" allow

# --- mechanism-guard: the CORE's own rules — a refused action is not re-issued ---------
# Coherence scan 2026-10-12: a skill named `gh api -X PUT .../pulls/<n>/merge` a "second
# legitimate form" after the permission layer refused `gh pr merge`. The core ships its own
# mechanism-rules.json; this reads THAT file (not a copy) through a fake enabled plugin whose
# install root is the core, so a broken pattern in the shipped file turns this red. It reuses
# the tool-rule fixture's dir (same fake user), so the plugin list below replaces the one above.
if CR=$(resolve mechanism-rules.json); then
  CRD=$(cd "$(dirname "$CR")" && pwd)
  printf '{"version":2,"plugins":{"core@fx":[{"installPath":"%s"}]}}' "$(native "$CRD")" \
    > "$TR/fakeuser/.claude/plugins/installed_plugins.json"
  printf '%s' '{"enabledPlugins":{"core@fx":true}}' > "$TR/fakeuser/.claude/settings.json"
  tr_probe "mechanism-guard/core rule: raw API merge" Bash command "gh api -X PUT repos/o/r/pulls/5/merge -f merge_method=merge" block
  tr_probe "mechanism-guard/core rule: --method PUT form" Bash command "gh api --method PUT repos/o/r/pulls/5/merge" block
  tr_probe "mechanism-guard/core rule: GET of the merge state" Bash command "gh api repos/o/r/pulls/5/merge" allow
  tr_probe "mechanism-guard/core rule: gh pr merge itself" Bash command "gh pr merge 5 --squash" allow
  tr_probe "mechanism-guard/core rule: marker without the operator" Bash command "gh api -X PUT repos/o/r/pulls/5/merge  # MECHANISM-OK: faster" block
  tr_probe "mechanism-guard/core rule: marker quoting the operator" Bash command "gh api -X PUT repos/o/r/pulls/5/merge  # MECHANISM-OK: operator 2026-10-12 \\\"merge it via the API\\\"" allow
  # CI is never waited for in the foreground (operator 2026-10-13: a core run takes ~15 min)
  tr_probe "mechanism-guard/core rule: ci-watch in the foreground" Bash command "bash core/scripts/ci-watch.sh pr o/r 5" block
  tr_probe "mechanism-guard/core rule: gh run watch in the foreground" Bash command "gh run watch 123 -R o/r" block
  tr_probe "mechanism-guard/core rule: gh pr checks --watch" Bash command "gh pr checks 5 -R o/r --watch" block
  tr_probe "mechanism-guard/core rule: gh pr checks once" Bash command "gh pr checks 5 -R o/r" allow
  tr_probe "mechanism-guard/core rule: ci-watch via Monitor" Monitor command "bash core/scripts/ci-watch.sh pr o/r 5" allow
  # 2026-10-25: the local CI mirror holds the session for minutes - detached only (Working Rule #13)
  tr_probe "mechanism-guard/core rule: ci-lint-local in the foreground" Bash command "bash scripts/ci-lint-local.sh lint" block
  tr_probe "mechanism-guard/core rule: ci-lint-local via Monitor" Monitor command "bash scripts/ci-lint-local.sh lint" allow
  tr_probe "mechanism-guard/core rule: the ci-lint-local fixture itself" Bash command "bash scripts/test-ci-lint-local.sh" allow
  # 2026-10-26: multi-line text belongs in a file - a commit message tripped a push ask rule
  tr_probe "mechanism-guard/core rule: multi-line commit -m" Bash command 'git -C /r commit -m \"fix: x\n\nbody names git -C <r> push to main\"' block
  tr_probe "mechanism-guard/core rule: one-line commit -m" Bash command 'git -C /r commit -m \"fix: one line\"' allow
  tr_probe "mechanism-guard/core rule: commit -F file" Bash command 'git -C /r commit -F /tmp/msg.txt' allow
  tr_probe "mechanism-guard/core rule: multi-line gh pr comment --body" Bash command 'gh pr comment 5 -R o/r --body \"line one\nline two\"' block
  tr_probe "mechanism-guard/core rule: gh pr comment --body-file" Bash command 'gh pr comment 5 -R o/r --body-file /tmp/b.md' allow
  tr_probe "mechanism-guard/core rule: two commands on two lines (control)" Bash command 'git -C /r commit -m \"one line\"\ngit -C /r log -1' allow
  # 2026-10-26: a self-written wait loop is the generic foreground wait - the name lists above never see it
  tr_probe "mechanism-guard/core rule: until-sleep wait loop in the foreground" Bash command "until [ -s out.txt ]; do sleep 10; done; cat out.txt" block
  tr_probe "mechanism-guard/core rule: while-sleep wait loop in the foreground" Bash command "while ! grep -q done log; do sleep 5; done" block
  tr_probe "mechanism-guard/core rule: wait loop via Monitor" Monitor command "until [ -s out.txt ]; do sleep 10; done; cat out.txt" allow
  tr_probe "mechanism-guard/core rule: a loop without sleep" Bash command "for f in a b; do echo \$f; done" allow
  tr_probe "mechanism-guard/core rule: a short retry with sub-second sleep" Bash command "until mkdir lock 2>/dev/null; do sleep 0.2; done" allow
  # class sweep of the same day: waiting scripts by name
  tr_probe "mechanism-guard/core rule: wait-mcp-reconnect in the foreground" Bash command "bash core/scripts/wait-mcp-reconnect.sh touchdesigner" block
  tr_probe "mechanism-guard/core rule: shared-memory-watch in the foreground" Bash command "bash core/scripts/shared-memory-watch.sh watch 300" block
  tr_probe "mechanism-guard/core rule: shared-memory-watch via Monitor" Monitor command "bash core/scripts/shared-memory-watch.sh watch 300" allow
  tr_probe "mechanism-guard/core rule: shared-memory-watch status" Bash command "bash core/scripts/shared-memory-watch.sh status" allow
  tr_probe "mechanism-guard/core rule: repo-activity-watch disarm" Bash command "bash core/scripts/repo-activity-watch.sh disarm" allow
  # collab-watch.sh has no status subcommand - the call arms the watch (measured 2026-10-26)
  tr_probe "mechanism-guard/core rule: collab-watch 'status' arms the watch" Bash command "bash core/scripts/collab-watch.sh status" block
  tr_probe "mechanism-guard/core rule: a watch script's own fixture" Bash command "bash scripts/test-shared-memory-watch.sh" allow
  # 2026-10-28: the name as an ARGUMENT of a reader is no call (grep/sed/awk on the script were
  # refused three times in one session, and a grep for "ci-watch.sh pr" once more)
  tr_probe "mechanism-guard/core rule: grep in ci-watch.sh" Bash command "grep -n usage core/scripts/ci-watch.sh" allow
  tr_probe "mechanism-guard/core rule: grep for the call text" Bash command "grep -n 'ci-watch.sh pr o/r 5' scripts/test-x.sh" allow
  tr_probe "mechanism-guard/core rule: sed on a watch script" Bash command "sed -n 1,25p core/scripts/shared-memory-watch.sh" allow
  tr_probe "mechanism-guard/core rule: ci-watch after ; still blocks" Bash command "echo go; bash core/scripts/ci-watch.sh pr o/r 5" block
  tr_probe "mechanism-guard/core rule: ci-watch inside until still blocks" Bash command "until bash core/scripts/ci-watch.sh pr o/r 5; do :; done" block
  tr_probe "mechanism-guard/core rule: wait script by bare path still blocks" Bash command "core/scripts/wait-mcp-reconnect.sh td" block
  tr_probe "mechanism-guard/core rule: wait script with an env prefix still blocks" Bash command "X=1 bash core/scripts/wait-link.sh sw1" block
  # The third foreground rule of the same shape (2026-10-28): a grep in the lint script and a test
  # string naming it were refused as "running the local CI mirror".
  tr_probe "mechanism-guard/core rule: grep in ci-lint-local.sh" Bash command "grep -n PY scripts/ci-lint-local.sh" allow
  tr_probe "mechanism-guard/core rule: lint name inside a node test string" Bash command "node -e 'f(\`ci-lint-local.sh\` 11/11)'" allow
  tr_probe "mechanism-guard/core rule: lint run by path still blocks" Bash command "bash /x/scripts/ci-lint-local.sh" block
  tr_probe "mechanism-guard/core rule: lint run after ; still blocks" Bash command "cd /x; scripts/ci-lint-local.sh" block
  # 2026-10-26: destructive pushes no permission pattern can catch (colon refspec, git -c ... push -f)
  tr_probe "mechanism-guard/core rule: delete by colon refspec" Bash command "git push origin :feat" block
  tr_probe "mechanism-guard/core rule: delete by colon refspec with -C" Bash command 'git -C /r push -q origin :feat' block
  tr_probe "mechanism-guard/core rule: force behind git -c" Bash command "git -c core.x=1 push -f origin b" block
  tr_probe "mechanism-guard/core rule: push HEAD:feat (control)" Bash command "git push origin HEAD:feat" allow
  tr_probe "mechanism-guard/core rule: push to a URL (control)" Bash command "git push https://example.com/o/r.git feat" allow
  tr_probe "mechanism-guard/core rule: plain feature push (control)" Bash command 'git -C /r push -u origin feat/x' allow
  # marketplace pin (ported 2026-10-28): writes block, reads pass
  tr_probe "mechanism-guard/core rule: pin edit by sed -i" Bash command "sed -i 's/v1/v2/' m/.claude-plugin/marketplace.json" block
  tr_probe "mechanism-guard/core rule: pin edit by redirect" Bash command "echo x > m/.claude-plugin/marketplace.json" block
  tr_probe "mechanism-guard/core rule: pin edit by script" Bash command "python3 bump.py m/.claude-plugin/marketplace.json" block
  tr_probe "mechanism-guard/core rule: pin edit by cp" Bash command "cp /tmp/x m/.claude-plugin/marketplace.json" block
  tr_probe "mechanism-guard/core rule: pin read by cat (control)" Bash command "cat m/.claude-plugin/marketplace.json" allow
  tr_probe "mechanism-guard/core rule: pin read by sed -n (control)" Bash command "sed -n 1,40p m/.claude-plugin/marketplace.json" allow
  tr_probe "mechanism-guard/core rule: pin read by awk (control)" Bash command "awk '/name/' m/.claude-plugin/marketplace.json" allow
  tr_probe "mechanism-guard/core rule: pin read by diff (control)" Bash command "diff m/.claude-plugin/marketplace.json /tmp/x" allow
  tr_probe "mechanism-guard/core rule: pin read by jq (control)" Bash command "jq .plugins m/.claude-plugin/marketplace.json" allow
  out=$(printf '{"tool_name":"Bash","tool_input":{"command":"bash core/scripts/ci-watch.sh pr o/r 5","run_in_background":true}}' \
        | CLAUDE_PROJECT_DIR="$(native "$TR/proj")" HOME="$TR/fakeuser" USERPROFILE="$(native "$TR/fakeuser")" node "$(resolve helpers/mechanism-guard.cjs)" 2>&1)
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then
    bad "mechanism-guard/core rule: ci-watch with run_in_background blocked what it should allow"
  else
    ok "mechanism-guard/core rule: ci-watch with run_in_background allows"
  fi
  # 2026-10-21: a brain WITHOUT the plugin had the core's own rules inert — the submodule's
  # file is the fallback. Control: same project without core/ stays allowed.
  printf '{"version":2,"plugins":{}}' > "$TR/fakeuser/.claude/plugins/installed_plugins.json"
  tr_probe "mechanism-guard/core rule without plugin, no submodule (control)" Bash command "gh api -X PUT repos/o/r/pulls/5/merge" allow
  mkdir -p "$TR/proj/core" && cp "$CR" "$TR/proj/core/mechanism-rules.json"
  tr_probe "mechanism-guard/core rule without plugin, from the submodule" Bash command "gh api -X PUT repos/o/r/pulls/5/merge" block
else
  skip "mechanism-guard/core rules (mechanism-rules.json)"
fi
rm -rf "$TR"

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
