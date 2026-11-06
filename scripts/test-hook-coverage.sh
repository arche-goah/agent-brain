#!/usr/bin/env bash
# covers: hook-coverage
#
# Fixture for scripts/hook-coverage.py with the plugin as the carrier of the core hooks
# (hooks/hooks.json, since 2.0.4). Four brains, both directions each:
#   1. plugin enabled and its install ships hooks/hooks.json, settings.json still carries a
#      copy of a core hook  -> the copy is named ("runs twice"), exit 1
#   2. same plugin, settings.json without core hooks                 -> silent, exit 0
#   3. plugin enabled but its install has NO hooks/ (a cache before 2.0.4) -> the hooks are
#      demanded from the brain's settings as before (missing lines), exit 1
#   4. no plugin at all, empty settings                               -> missing lines, exit 1
# The config dir is a fixture dir, so the runner's real plugins never leak into the check.
#
# Usage: bash scripts/test-hook-coverage.sh   (exit 0 = all fixtures pass)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
resolve() { for c in "core/$1" "$1"; do [ -f "$ROOT/$c" ] && { printf '%s' "$ROOT/$c"; return 0; }; done; return 1; }
HC=$(resolve scripts/hook-coverage.py) || { echo "  --  hook-coverage.py not in this layout"; exit 0; }
CORE="$(dirname "$(dirname "$HC")")"
[ -f "$CORE/hooks/hooks.json" ] || { echo "  --  $CORE ships no hooks/hooks.json"; exit 0; }

PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
# Paths travel INSIDE data (installPath in installed_plugins.json, CLAUDE_CONFIG_DIR, the brain
# root as argv): a Git Bash /tmp path does not resolve for python (docs/os-traps.md OS-3).
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
NT=$(native "$T")
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

# A brain: the consumed core (helpers, hooks, templates) plus instance data that keeps every
# other hook-coverage line silent, so the lines below are about the plugin only.
make_brain() { # make_brain <dir>
  mkdir -p "$1/core/templates" "$1/core/helpers" "$1/core/hooks" "$1/.claude/rules"
  cp "$CORE/templates/settings.json" "$1/core/templates/"
  cp "$CORE/hooks/hooks.json" "$1/core/hooks/"
  cp "$CORE"/helpers/*.cjs "$CORE"/helpers/*.sh "$1/core/helpers/" 2>/dev/null
  printf '{"names": ["placeholder"], "instances": []}\n' > "$1/.claude/rules/leak-names.json"
  printf '{"domains": [], "inert_ok": "fixture brain, no live systems"}\n' > "$1/.claude/rules/live-read.json"
  printf '{"suites": [], "inert_ok": "fixture brain, no live systems"}\n' > "$1/.claude/rules/live-watchdog.json"
  # the template without hooks, as the brain's settings: permissions granted, no hooks
  cp "$CORE/templates/settings.json" "$1/.claude/settings.json"
}

# A config dir with the plugin installed at <cache> and enabled in the user settings.
make_cfg() { # make_cfg <cfgdir> <cache dir> <ship hooks: yes|no>
  mkdir -p "$1/plugins" "$2/.claude-plugin"
  printf '{"name": "brain-core", "version": "9.9.9"}\n' > "$2/.claude-plugin/plugin.json"
  if [ "$3" = yes ]; then mkdir -p "$2/hooks"; cp "$CORE/hooks/hooks.json" "$2/hooks/"; fi
  "$PY" -c 'import json,sys; json.dump({"plugins":{"brain-core-next@fixture":[{"scope":"user","installPath":sys.argv[2],"version":"9.9.9"}]}},open(sys.argv[1]+"/plugins/installed_plugins.json","w"))' "$(native "$1")" "$(native "$2")"
  printf '{"enabledPlugins": {"brain-core-next@fixture": true}}\n' > "$1/settings.json"
}

copy_core_hook() { # copy_core_hook <brain>: a verbatim copy of file-guard into settings.json
  "$PY" -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p,encoding="utf-8"))
d["hooks"]={"PreToolUse":[{"matcher":"Write|Edit|MultiEdit","hooks":[{"type":"command","command":"node \"$CLAUDE_PROJECT_DIR/core/helpers/file-guard.cjs\"","timeout":10,"onFailure":"block"}]}]}
json.dump(d,open(p,"w",encoding="utf-8"),indent=2)' "$1/.claude/settings.json"
}

# 1) plugin ships, settings carries a copy -> duplicate named
B="$T/dup"; make_brain "$B"; make_cfg "$T/cfg-ship" "$T/cache-ship" yes; copy_core_hook "$B"
out="$(CLAUDE_CONFIG_DIR="$T/cfg-ship" "$PY" "$HC" "$B" 2>&1)"; rc=$?
case "$rc:$out" in
  1:*"PreToolUse: file-guard.cjs runs twice"*"drop the copy"*) ok "a core hook copied next to the plugin is named as a duplicate (exit 1)";;
  *) bad "duplicate case: rc=$rc out='$(printf '%s' "$out" | head -1)'";;
esac
case "$out" in
  *"PreToolUse: node"*) bad "duplicate case also reports plugin hooks as missing: '$(printf '%s' "$out" | grep -a 'PreToolUse: node' | head -1)'";;
  *) ok "plugin-shipped hooks are not demanded from settings.json";;
esac

# 2) plugin ships, settings clean -> silent
B="$T/clean"; make_brain "$B"
out="$(CLAUDE_CONFIG_DIR="$T/cfg-ship" "$PY" "$HC" "$B" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "plugin ships the hooks, settings without a copy: silent (negative control)"
else
  bad "clean case: rc=$rc out='$(printf '%s' "$out" | head -1)'"
fi
#    ... and a plugin-shipped gate whose instance data is missing is still named (the shipped
#    hooks count as wired, so the inert check sees them).
rm -f "$B/.claude/rules/live-read.json"
out="$(CLAUDE_CONFIG_DIR="$T/cfg-ship" "$PY" "$HC" "$B" 2>&1)"; rc=$?
case "$rc:$out" in
  1:*"live-read-gate.cjs is wired but .claude/rules/live-read.json does not exist"*) ok "a plugin-shipped gate without its data file is still named";;
  *) bad "inert case under the plugin: rc=$rc out='$(printf '%s' "$out" | head -1)'";;
esac

#    ... and an instance hook whose file name merely ENDS in a shipped name is no copy
B="$T/suffix"; make_brain "$B"
"$PY" -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p,encoding="utf-8"))
d["hooks"]={"PreToolUse":[{"matcher":"AskUserQuestion","hooks":[{"type":"command","command":"node \"$CLAUDE_PROJECT_DIR/scripts/hooks/autonomous-question-gate.cjs\"","timeout":10}]}]}
json.dump(d,open(p,"w",encoding="utf-8"),indent=2)' "$B/.claude/settings.json"
out="$(CLAUDE_CONFIG_DIR="$T/cfg-ship" "$PY" "$HC" "$B" 2>&1)"
case "$out" in
  *"runs twice"*) bad "autonomous-question-gate.cjs taken for a copy of question-gate.cjs: '$(printf '%s' "$out" | grep -a 'runs twice' | head -1)'";;
  *) ok "a hook whose file name ends in a shipped name is not a duplicate";;
esac

#    ... and an instance script that merely SHARES a shipped file name is another hook (a
#    messaging notify.cjs next to the core's sound notify.cjs, measured 2026-11-02), while a
#    copy of a core hook at another path is still named
B="$T/samename"; make_brain "$B"; mkdir -p "$B/scripts/hooks" "$B/hooks-copy"
printf '%s\n' '// posts a message to a chat bot; unrelated to the core sound hook' 'process.exit(0);' > "$B/scripts/hooks/notify.cjs"
"$PY" -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p,encoding="utf-8"))
d["hooks"]={"Notification":[{"hooks":[{"type":"command","command":"node \"$CLAUDE_PROJECT_DIR/scripts/hooks/notify.cjs\" wait"}]}]}
json.dump(d,open(p,"w",encoding="utf-8"),indent=2)' "$B/.claude/settings.json"
out="$(CLAUDE_CONFIG_DIR="$T/cfg-ship" "$PY" "$HC" "$B" 2>&1)"
case "$out" in
  *"notify.cjs runs twice"*) bad "an instance script with a shipped file name taken for a copy: '$(printf '%s' "$out" | grep -a 'runs twice' | head -1)'";;
  *) ok "an instance script that shares a shipped file name is not a duplicate";;
esac
{ cat "$B/core/helpers/file-guard.cjs"; echo '// a stale local edit'; } > "$B/hooks-copy/file-guard.cjs"
"$PY" -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p,encoding="utf-8"))
d["hooks"]={"PreToolUse":[{"matcher":"Write|Edit|MultiEdit","hooks":[{"type":"command","command":"node \""+sys.argv[2]+"/hooks-copy/file-guard.cjs\"","onFailure":"block"}]}]}
json.dump(d,open(p,"w",encoding="utf-8"),indent=2)' "$B/.claude/settings.json" "$(native "$B")"
out="$(CLAUDE_CONFIG_DIR="$T/cfg-ship" "$PY" "$HC" "$B" 2>&1)"
case "$out" in
  *"PreToolUse: file-guard.cjs runs twice"*) ok "a copy of a core hook at another path is still named as a duplicate";;
  *) bad "copy at another path not named: '$(printf '%s' "$out" | head -1)'";;
esac

# 3) plugin enabled, cache without hooks/ -> the brain must wire them itself (as before 2.0.4)
B="$T/old"; make_brain "$B"; make_cfg "$T/cfg-old" "$T/cache-old" no
out="$(CLAUDE_CONFIG_DIR="$T/cfg-old" "$PY" "$HC" "$B" 2>&1)"; rc=$?
case "$rc:$out" in
  1:*"Stop: node"*"stop-dispatcher"*) ok "a plugin cache without hooks/ leaves the demand on settings.json (missing lines)";;
  *) bad "old-cache case: rc=$rc out='$(printf '%s' "$out" | head -1)'";;
esac
case "$out" in
  *"runs twice"*) bad "old-cache case reports a duplicate although nothing is shipped";;
  *) ok "no duplicate line without a shipped hooks.json";;
esac

# 4) no plugin, empty settings -> missing lines
B="$T/none"; make_brain "$B"; mkdir -p "$T/cfg-none"; printf '{}\n' > "$B/.claude/settings.json"
out="$(CLAUDE_CONFIG_DIR="$T/cfg-none" "$PY" "$HC" "$B" 2>&1)"; rc=$?
case "$rc:$out" in
  1:*"Stop: node"*) ok "no plugin: the hooks of core/hooks/hooks.json are demanded from settings.json";;
  *) bad "no-plugin case: rc=$rc out='$(printf '%s' "$out" | head -1)'";;
esac

#    ... a matcher `.*` covers every tool (never "runs only on"), a narrower one is named, and an
#    instance script that only shares the file name does not stand in for the core hook
wire_input_guard() { # wire_input_guard <brain> <matcher> <command>: hooks.json as settings, one hook changed
  "$PY" -c 'import json,sys
p,m,c=sys.argv[1:4]; d=json.load(open(p,encoding="utf-8")); h=json.load(open(sys.argv[4],encoding="utf-8"))
for g in h["hooks"]["PreToolUse"]:
    for x in g["hooks"]:
        if "no-input-control.cjs" in x["command"]: g["matcher"]=m; x["command"]=c
d["hooks"]=h["hooks"]; json.dump(d,open(p,"w",encoding="utf-8"),indent=2)' "$1/.claude/settings.json" "$2" "$3" "$1/core/hooks/hooks.json"
}
B="$T/matcher"; make_brain "$B"
wire_input_guard "$B" ".*" 'node "$CLAUDE_PROJECT_DIR/core/helpers/no-input-control.cjs"'
out="$(CLAUDE_CONFIG_DIR="$T/cfg-none" "$PY" "$HC" "$B" 2>&1)"
case "$out" in
  *"no-input-control.cjs runs only on"*) bad "matcher .* taken for a narrower one: '$(printf '%s' "$out" | grep -a 'runs only on' | head -1)'";;
  *) ok "a matcher .* covers every tool";;
esac
wire_input_guard "$B" "Bash" 'node "$CLAUDE_PROJECT_DIR/core/helpers/no-input-control.cjs"'
out="$(CLAUDE_CONFIG_DIR="$T/cfg-none" "$PY" "$HC" "$B" 2>&1)"
case "$out" in
  *"no-input-control.cjs runs only on Bash"*) ok "a narrower matcher is named (negative control)";;
  *) bad "matcher Bash not named as narrower: '$(printf '%s' "$out" | head -1)'";;
esac
mkdir -p "$B/scripts/hooks"; printf '%s\n' '// an unrelated instance script' > "$B/scripts/hooks/no-input-control.cjs"
wire_input_guard "$B" ".*" 'node "$CLAUDE_PROJECT_DIR/scripts/hooks/no-input-control.cjs"'
out="$(CLAUDE_CONFIG_DIR="$T/cfg-none" "$PY" "$HC" "$B" 2>&1)"
case "$out" in
  *"PreToolUse: node"*"core/helpers/no-input-control.cjs"*) ok "a same-named instance script does not count as the core hook (still missing)";;
  *) bad "same-named instance script counted as the core hook: '$(printf '%s' "$out" | head -1)'";;
esac
#    ... and a broken path that only ends in the core's file name does not stand in for it either
#    (review on the macOS instance 2026-11-02), while the duplicate check keeps the careful side
wire_input_guard "$B" ".*" 'node "$CLAUDE_PROJECT_DIR/scripts/gone/no-input-control.cjs"'
out="$(CLAUDE_CONFIG_DIR="$T/cfg-none" "$PY" "$HC" "$B" 2>&1)"
case "$out" in
  *"PreToolUse: node"*"core/helpers/no-input-control.cjs"*) ok "a broken same-named path does not count as the core hook (still missing)";;
  *) bad "broken same-named path counted as the core hook: '$(printf '%s' "$out" | head -1)'";;
esac
B="$T/gone"; make_brain "$B"
"$PY" -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p,encoding="utf-8"))
d["hooks"]={"PreToolUse":[{"matcher":"Write|Edit|MultiEdit","hooks":[{"type":"command","command":"node \"$CLAUDE_PROJECT_DIR/old/file-guard.cjs\"","onFailure":"block"}]}]}
json.dump(d,open(p,"w",encoding="utf-8"),indent=2)' "$B/.claude/settings.json"
out="$(CLAUDE_CONFIG_DIR="$T/cfg-ship" "$PY" "$HC" "$B" 2>&1)"
case "$out" in
  *"PreToolUse: file-guard.cjs runs twice"*) ok "a broken same-named path next to the plugin is still named as a duplicate (careful side)";;
  *) bad "broken same-named path next to the plugin not named: '$(printf '%s' "$out" | head -1)'";;
esac

# 5) --runs: where one helper runs (onboarding-verify check 5) — the plugin's hooks.json counts,
#    a plugin cache without hooks/ and no settings line is "nowhere" (exit 1, no line)
out="$(CLAUDE_CONFIG_DIR="$T/cfg-ship" "$PY" "$HC" --runs SessionStart session-bootup.sh "$T/clean" 2>&1)"; rc=$?
case "$rc:$out" in
  "0:the plugin brain-core-next@fixture (hooks/hooks.json)") ok "--runs names the plugin that ships the bootup hook (exit 0)";;
  *) bad "--runs plugin case: rc=$rc out='$out'";;
esac
out="$(CLAUDE_CONFIG_DIR="$T/cfg-old" "$PY" "$HC" --runs SessionStart session-bootup.sh "$T/old" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && [ -z "$out" ]; then ok "--runs: no settings line, no shipped hooks.json -> nowhere (exit 1)"
else bad "--runs nowhere case: rc=$rc out='$out'"; fi
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash core/helpers/session-bootup.sh"}]}]}}\n' > "$T/old/.claude/settings.local.json"
out="$(CLAUDE_CONFIG_DIR="$T/cfg-old" "$PY" "$HC" --runs SessionStart session-bootup.sh "$T/old" 2>&1)"; rc=$?
case "$rc:$out" in
  "0:.claude/settings.local.json") ok "--runs names the settings scope that wires it";;
  *) bad "--runs settings case: rc=$rc out='$out'";;
esac

if [ "$fail" -eq 0 ]; then echo "hook-coverage fixtures: ALL passed"; else echo "hook-coverage fixtures: FAILED"; fi
exit "$fail"
