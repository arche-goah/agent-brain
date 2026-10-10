#!/usr/bin/env bash
# Fixture for scripts/local-machinery.py — both directions for every class, plus the
# carrier-coverage self-test: a brain with ONE planted item per carrier type, every one must be
# reported, and removing a carrier from the scanner must turn its case red (negative control).
# The real home and the real global git config never reach the script: --home and
# GIT_CONFIG_GLOBAL point into the temp dir.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
# A path that a native process reads from DATA (json, plist, git config) goes through cygpath
# on Windows (os-traps OS-3); argv paths are converted by Git Bash itself.
nat() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }

mkdir -p "$T/fakehome/Library/LaunchAgents"
export GIT_CONFIG_GLOBAL="$(nat "$T/gitconfig")" GIT_CONFIG_NOSYSTEM=1
: > "$T/gitconfig"
LM() { "$PY" "$HERE/local-machinery.py" --home "$T/fakehome" "$@"; }
run() { LM --repo "$T/b" --today "${TODAY:-2026-10-08}" "$@"; }

mk() { # $1 = settings hooks json, $2 = stop-checks json, $3 = declarations json
  rm -rf "$T/b"; mkdir -p "$T/b/.claude/rules"
  printf '%s' "$1" > "$T/b/.claude/settings.json"
  [[ -n "$2" ]] && printf '%s' "$2" > "$T/b/.claude/rules/stop-checks.json"
  [[ -n "$3" ]] && printf '%s' "$3" > "$T/b/.claude/rules/local-machinery.json"
  mkdir -p "$T/b/core/helpers"; : > "$T/b/core/helpers/a.cjs"; : > "$T/b/core/helpers/b.cjs"
  run
}
H() { printf '{"hooks":{"Stop":[{"hooks":[%s]}]}}' "$1"; }
C() { printf '{"type":"command","command":"%s"}' "$1"; }
CORE_HOOK="$(H "$(C 'node \"$CLAUDE_PROJECT_DIR/core/helpers/a.cjs\"')")"
X_HOOK="$(H "$(C 'node \"$CLAUDE_PROJECT_DIR/scripts/hooks/x.cjs\"')")"
decl() { printf '%s' "$1" > "$T/b/.claude/rules/local-machinery.json"; }

# --- hooks and stop checks ---------------------------------------------------------------
out=$(mk "$CORE_HOOK" '[{"cmd":"core/helpers/b.cjs"}]' '')
[[ -z "$out" ]] && ok "core-only-silent" || bad "core-only-silent: $out"

out=$(mk "$X_HOOK" '' '')
grep -q 'item(s) without a declaration (hook 1)' <<< "$out" && grep -q 'x.cjs' <<< "$out" \
  && grep -q '^local machinery summary: items=1 .*undeclared=1' <<< "$out" \
  && ok "undeclared-instance-named-with-summary" || bad "undeclared-instance-named-with-summary: $out"

mk "$X_HOOK" '' '' >/dev/null
mkdir -p "$T/b/scripts/hooks"; printf '// opens the slicer of plotter-7\n' > "$T/b/scripts/hooks/x.cjs"
decl '{"instance":{"scripts/hooks/x.cjs":{"why":"renders only for this printer","evidence":"plotter-7"}}}'
out=$(run); [[ -z "$out" ]] && ok "declared-with-evidence-silent" || bad "declared-with-evidence-silent: $out"
decl '{"instance":{"scripts/hooks/x.cjs":"renders only for this printer"}}'
out=$(run); grep -q '^!! local machinery: 1 instance declaration(s) give a reason without evidence: scripts/hooks/x.cjs' <<< "$out" \
  && ok "string-declaration-reported-without-evidence" || bad "string-declaration-reported-without-evidence: $out"
decl '{"instance":{"scripts/hooks/x.cjs":{"why":"renders only for this printer","evidence":"venue-hall-b"}}}'
out=$(run); grep -q '^!! local machinery: 1 item(s) do not contain the evidence.*x.cjs (venue-hall-b)' <<< "$out" \
  && ok "evidence-not-in-content-loud" || bad "evidence-not-in-content-loud: $out"

# Outside hooks: a dev checkout that EXISTS (its path travels as data inside the hook command).
mkdir -p "$T/dev/helpers"; : > "$T/dev/helpers/d.cjs"; : > "$T/dev/helpers/g.cjs"
DEV="$(nat "$T/dev")"
D_HOOK="$(H "$(C "node $DEV/helpers/d.cjs")")"
out=$(mk "$D_HOOK" '' '')
grep -q '^!! local machinery: 1 item(s) run from outside' <<< "$out" && ok "undeclared-outside-loud" || bad "undeclared-outside-loud: $out"
out=$(mk "$D_HOOK" '' "{\"alpha\":{\"$DEV/\":{\"until\":\"2026-10-20\",\"why\":\"alpha\"}}}")
[[ -z "$out" ]] && ok "alpha-in-date-silent" || bad "alpha-in-date-silent: $out"
out=$(mk "$D_HOOK" '' "{\"alpha\":{\"$DEV/\":{\"until\":\"2026-10-01\",\"why\":\"alpha\"}}}")
grep -q 'past their date' <<< "$out" && ok "alpha-expired-loud" || bad "alpha-expired-loud: $out"
out=$(mk "$D_HOOK" '' "{\"alpha\":{\"$DEV/\":{\"why\":\"no date\"}}}")
grep -q 'past their date' <<< "$out" && ok "alpha-without-date-loud" || bad "alpha-without-date-loud: $out"
out=$(mk "$CORE_HOOK" "[{\"cmd\":\"$DEV/helpers/g.cjs\"}]" '')
grep -q 'run from outside' <<< "$out" && grep -q 'g.cjs' <<< "$out" && ok "stop-check-outside-counted" || bad "stop-check-outside-counted: $out"

# Missing targets: a hook or stop check whose script is gone stops running without a sound.
out=$(mk "$CORE_HOOK" "[{\"cmd\":\"$DEV/helpers/gone.cjs\"}]" "{\"alpha\":{\"$DEV/\":{\"until\":\"2026-10-20\",\"why\":\"alpha\"}}}")
grep -q '^!! local machinery: 1 hook or stop-check target(s) do not exist: stop-check: .*dev/helpers/gone.cjs' <<< "$out" \
  && ok "missing-stop-check-target-loud-even-when-declared" || bad "missing-stop-check-target-loud-even-when-declared: $out"
out=$(mk "$(H "$(C 'node \"$CLAUDE_PROJECT_DIR/core/helpers/gone.cjs\"')")" '' '')
grep -q 'target(s) do not exist: hook: core/helpers/gone.cjs' <<< "$out" && ok "missing-core-hook-target-loud" || bad "missing-core-hook-target-loud: $out"
# A user-level hook spelled with %USERPROFILE% (cmd /c on Windows): present = silent, gone = loud.
mkdir -p "$T/fakehome/.claude/helpers"; : > "$T/fakehome/.claude/helpers/toast.cjs"
out=$(mk "$(H "$(C 'cmd /c node \"%USERPROFILE%\\.claude\\helpers\\toast.cjs\" stop')")" '' '')
grep -q 'do not exist' <<< "$out" && bad "userprofile-hook-present-silent: $out" || ok "userprofile-hook-present-silent"
out=$(mk "$(H "$(C 'cmd /c node \"%USERPROFILE%\\.claude\\helpers\\gone.cjs\" stop')")" '' '')
grep -q 'do not exist.*gone.cjs' <<< "$out" && ok "userprofile-hook-gone-loud" || bad "userprofile-hook-gone-loud: $out"
rm -f "$T/fakehome/.claude/helpers/toast.cjs"

# Two contradicting places: declared manual, yet wired; declared both instance and alpha.
mk "$X_HOOK" '' '' >/dev/null
mkdir -p "$T/b/scripts/hooks"; printf '// x\n' > "$T/b/scripts/hooks/x.cjs"
printf '{"manual":["x.cjs"]}' > "$T/b/.claude/rules/manual-tools.json"
out=$(run); grep -q 'declared in two contradicting places: scripts/hooks/x.cjs (manual-tools.json, yet wired as hook)' <<< "$out" \
  && ok "manual-but-wired-contradiction-loud" || bad "manual-but-wired-contradiction-loud: $out"
printf '{"manual":["other.sh"]}' > "$T/b/.claude/rules/manual-tools.json"
out=$(run); ! grep -q 'contradicting' <<< "$out" && ok "manual-list-without-it-silent" || bad "manual-list-without-it-silent: $out"
decl '{"instance":{"scripts/hooks/":{"why":"w","evidence":"// x"}},"alpha":{"scripts/hooks/x.cjs":{"until":"2026-10-20","why":"a"}}}'
out=$(run); grep -q "declared both instance 'scripts/hooks/' and alpha 'scripts/hooks/x.cjs'" <<< "$out" \
  && ok "instance-and-alpha-contradiction-loud" || bad "instance-and-alpha-contradiction-loud: $out"
out=$(mk '{' '' ''); rc=$?
[[ $rc -eq 0 && -z "$out" ]] && ok "broken-settings-silent-exit0" || bad "broken-settings-silent-exit0 rc=$rc: $out"

# --- edited core -------------------------------------------------------------------------
mk "$CORE_HOOK" '' '' >/dev/null
mkdir -p "$T/b/core"; git -C "$T/b/core" init -q
printf 'x\n' > "$T/b/core/rule.md"; git -C "$T/b/core" add rule.md
git -C "$T/b/core" -c user.email=t@t -c user.name=t commit -q -m init
out=$(run); [[ -z "$out" ]] && ok "clean-core-silent" || bad "clean-core-silent: $out"
printf 'y\n' >> "$T/b/core/rule.md"
out=$(run); grep -q 'core file(s) edited inside core/: rule.md' <<< "$out" && ok "edited-core-loud" || bad "edited-core-loud: $out"

# --- scripts: shadow, listing, declarations, alpha ----------------------------------------
mk "$CORE_HOOK" '' '' >/dev/null
mkdir -p "$T/b/core/scripts" "$T/b/scripts"
printf 'x\n' > "$T/b/core/scripts/invariant-check.py"; printf 'x\n' > "$T/b/scripts/invariant-check.py"
out=$(run); grep -q '^!! local machinery: 1 instance item(s) shadow a core item of the same name: scripts/invariant-check.py' <<< "$out" \
  && ok "shadow-script-loud" || bad "shadow-script-loud: $out"
printf 'import runpy\nrunpy.run_path("core/scripts/invariant-check.py")\n' > "$T/b/scripts/invariant-check.py"
out=$(run); grep -q '^!! local machinery: 1 same-named instance wrapper(s) only call the core item: scripts/invariant-check.py' <<< "$out" \
  && ! grep -q 'shadow a core item' <<< "$out" && ok "thin-wrapper-named-as-wrapper-not-shadow" || bad "thin-wrapper-named-as-wrapper-not-shadow: $out"
rm -f "$T/b/scripts/invariant-check.py"
printf 'ssh rig-switch-a\n' > "$T/b/scripts/rig-check.sh"; printf 'x\n' > "$T/b/scripts/test-rig-check.sh"
out=$(run); grep -q 'without a declaration (script 1).*: scripts/rig-check.sh' <<< "$out" && ! grep -q 'test-rig-check' <<< "$out" \
  && ok "undeclared-script-listed-fixture-skipped" || bad "undeclared-script-listed-fixture-skipped: $out"
decl '{"instance":{"scripts/rig-":{"why":"probes this venue only","evidence":"rig-switch-a"}}}'
out=$(run); [[ -z "$out" ]] && ok "declared-prefix-with-evidence-silent" || bad "declared-prefix-with-evidence-silent: $out"
decl '{"alpha":{"scripts/rig-check.sh":{"until":"2026-10-20","why":"core port"}}}'
out=$(run); [[ -z "$out" ]] && ok "alpha-script-in-date-silent" || bad "alpha-script-in-date-silent: $out"
out=$(TODAY=2026-10-21 run); grep -q 'past their date.*scripts/rig-check.sh' <<< "$out" && ok "alpha-script-expired-loud" || bad "alpha-script-expired-loud: $out"

# --- identity tokens: an undeclared item without any is presumably general ----------------
decl '{"identity_tokens":{"devices":["rig-switch-a"],"hosts":["203.0.113.7"]}}'
out=$(run); grep -q 'without a declaration (script 1)' <<< "$out" && ! grep -q 'presumably general' <<< "$out" \
  && ok "item-with-identity-token-undeclared-not-general" || bad "item-with-identity-token-undeclared-not-general: $out"
printf 'echo generic retry helper\n' > "$T/b/scripts/rig-check.sh"
out=$(run); grep -q '^!! local machinery: 1 undeclared item(s) contain none of this brain.s identity tokens, presumably general: scripts/rig-check.sh' <<< "$out" \
  && grep -q 'general=1' <<< "$out" && ok "item-without-identity-token-general-loud" || bad "item-without-identity-token-general-loud: $out"
printf 'ping 203.0.113.70\n' > "$T/b/scripts/rig-check.sh"   # a longer IP is not the token
out=$(run); grep -q 'presumably general' <<< "$out" && ok "identity-token-word-boundary" || bad "identity-token-word-boundary: $out"

# --- near-duplicates of core tools --------------------------------------------------------
rm -f "$T/b/.claude/rules/local-machinery.json"
printf 'x\n' > "$T/b/core/scripts/wait-mcp-reconnect.sh"; printf 'x\n' > "$T/b/core/scripts/brain-check.sh"
printf 'restart helper\n' > "$T/b/scripts/wait-mcp-restart.sh"
out=$(run); grep -q 'near-duplicate of a core item: scripts/wait-mcp-restart.sh (core scripts/wait-mcp-reconnect.sh)' <<< "$out" \
  && ok "near-duplicate-named" || bad "near-duplicate-named: $out"
grep -q 'rig-check.sh (core' <<< "$out" && bad "one-shared-token-is-not-a-duplicate: $out" || ok "one-shared-token-is-not-a-duplicate"
decl '{"instance":{"scripts/wait-mcp-restart.sh":{"why":"x","evidence":"restart","distinct_from":"wait-mcp-reconnect"}}}'
out=$(run); ! grep -q 'near-duplicate' <<< "$out" && ! grep -q 'wait-mcp-restart' <<< "$out" && ok "distinct-from-silences-duplicate" || bad "distinct-from-silences-duplicate: $out"

# --- skill and workflow shadows -----------------------------------------------------------
mk "$CORE_HOOK" '' '' >/dev/null
mkdir -p "$T/b/core/skills/caveman" "$T/b/core/workflows" "$T/b/.claude/skills/caveman" "$T/b/.claude/workflows"
printf 'x\n' > "$T/b/core/skills/caveman/SKILL.md"; printf 'x\n' > "$T/b/.claude/skills/caveman/SKILL.md"
printf 'x\n' > "$T/b/core/workflows/brain-scan.js"; printf 'x\n' > "$T/b/.claude/workflows/brain-scan.js"
out=$(run); grep -q 'shadow a core item.*\.claude/skills/caveman' <<< "$out" && grep -q 'shadow a core item.*\.claude/workflows/brain-scan.js' <<< "$out" \
  && ok "skill-and-workflow-shadow-loud" || bad "skill-and-workflow-shadow-loud: $out"
rm -rf "$T/b/.claude/skills/caveman" "$T/b/.claude/workflows/brain-scan.js"
ln -s "$T/b/core/skills/caveman" "$T/b/.claude/skills/caveman" 2>/dev/null
if [[ -L "$T/b/.claude/skills/caveman" ]]; then
  out=$(run); [[ -z "$out" ]] && ok "skill-symlink-to-core-silent" || bad "skill-symlink-to-core-silent: $out"
else
  echo "  SKIP skill-symlink-to-core-silent (no symlinks on this platform)"
fi

# --- plugins: core and suites are not items ------------------------------------------------
mk '{"enabledPlugins":{"brain-core@m":true,"brain-core-next@m":true,"td@m":true,"off@m":false}}' '' '' >/dev/null
mkdir -p "$T/b/config"; printf '{"repos":{"td-suite":{"kind":"suite","consumer_plugin":"td@m"}}}' > "$T/b/config/ecosystem.json"
out=$(run); [[ -z "$out" ]] && ok "core-suite-disabled-plugins-silent" || bad "core-suite-disabled-plugins-silent: $out"
printf '{"repos":{}}' > "$T/b/config/ecosystem.json"
out=$(run); grep -q 'plugin:td@m' <<< "$out" && ! grep -q 'brain-core' <<< "$out" && ! grep -q 'off@m' <<< "$out" \
  && ok "unlisted-plugin-reported" || bad "unlisted-plugin-reported: $out"

# --- git hooks: global hooksPath outside the brain ----------------------------------------
mk "$CORE_HOOK" '' '' >/dev/null; git -C "$T/b" init -q
mkdir -p "$T/ghooks"; printf '#!/bin/sh\n' > "$T/ghooks/pre-push"; printf 'x\n' > "$T/ghooks/helper.py"
out=$(run); [[ -z "$out" ]] && ok "no-hooks-path-silent" || bad "no-hooks-path-silent: $out"
git config --file "$T/gitconfig" core.hooksPath "$(nat "$T/ghooks")"
out=$(run); grep -q 'run from outside.*ghooks/pre-push' <<< "$out" && ! grep -q 'helper.py' <<< "$out" \
  && ok "global-git-hook-outside-loud" || bad "global-git-hook-outside-loud: $out"
: > "$T/gitconfig"

# --- scheduled jobs ------------------------------------------------------------------------
mk "$CORE_HOOK" '' '' >/dev/null
printf '<plist><string>/opt/other/run.sh</string></plist>\n' > "$T/fakehome/Library/LaunchAgents/other.plist"
out=$(run); [[ -z "$out" ]] && ok "foreign-scheduled-job-silent" || bad "foreign-scheduled-job-silent: $out"
rm -f "$T/fakehome/Library/LaunchAgents/other.plist"
mkdir -p "$T/fakehome2"
out=$(LM --home "$T/fakehome2" --repo "$T/b" --today 2026-10-08)
if command -v schtasks >/dev/null 2>&1; then
  ! grep -q 'unchecked=scheduled' <<< "$out" && ok "scheduled-checked-via-schtasks" || bad "scheduled-checked-via-schtasks: $out"
else
  grep -q '^local machinery summary: .* unchecked=scheduled$' <<< "$out" && ok "scheduled-unchecked-said-once" || bad "scheduled-unchecked-said-once: $out"
fi

# --- tool sources off main (MCP server path or skill symlink into a suite checkout) -------
mkdir -p "$T/suite/skills/s1"; printf 'x\n' > "$T/suite/server.js"
git -C "$T/suite" init -q -b main; git -C "$T/suite" add -A
git -C "$T/suite" -c user.email=t@t -c user.name=t commit -q -m init
mk "$CORE_HOOK" '' '' >/dev/null
printf '{"mcpServers":{"s":{"command":"node","args":["%s"]}}}' "$(nat "$T/suite/server.js")" > "$T/b/.mcp.json"
out=$(run); [[ -z "$out" ]] && ok "mcp-source-on-main-silent" || bad "mcp-source-on-main-silent: $out"
git -C "$T/suite" checkout -q -b feat/x
out=$(run); grep -q 'suite@feat/x' <<< "$out" && ok "mcp-source-off-main-loud" || bad "mcp-source-off-main-loud: $out"
decl "$(printf '{"alpha":{"%s":{"until":"2026-10-20","why":"alpha"}}}' "$(nat "$T/suite")")"
out=$(run); [[ -z "$out" ]] && ok "off-main-declared-alpha-silent" || bad "off-main-declared-alpha-silent: $out"
rm -f "$T/b/.mcp.json" "$T/b/.claude/rules/local-machinery.json"; mkdir -p "$T/b/.claude/skills"
ln -s "$T/suite/skills/s1" "$T/b/.claude/skills/s1" 2>/dev/null
if [[ -L "$T/b/.claude/skills/s1" ]]; then
  out=$(run); grep -q 'suite@feat/x' <<< "$out" && ok "skill-symlink-off-main-loud" || bad "skill-symlink-off-main-loud: $out"
else
  echo "  SKIP skill-symlink-off-main-loud (no symlinks on this platform)"
fi

# --- carrier coverage: one planted item per carrier, each reported, each control red -----
rm -rf "$T/b"; mkdir -p "$T/b/.claude/rules" "$T/b/.claude/hooks" "$T/b/.claude/skills/myskill" \
  "$T/b/.claude/workflows" "$T/b/.claude/output-styles" "$T/b/.claude/agents" "$T/b/.claude/commands" \
  "$T/b/githooks" "$T/b/tools" "$T/plug"
git -C "$T/b" init -q; git -C "$T/b" config core.hooksPath githooks
printf '%s' "$(H "$(C 'node \"$CLAUDE_PROJECT_DIR/.claude/hooks/h.cjs\"')" | sed 's/}$/,"enabledPlugins":{"extra@mkt":true}}/')" > "$T/b/.claude/settings.json"
printf '[{"cmd":".claude/hooks/sc.cjs"}]' > "$T/b/.claude/rules/stop-checks.json"
printf '{"mcpServers":{"srv":{"command":"node","args":["tools/srv.js"]}}}' > "$T/b/.mcp.json"
for f in .claude/hooks/h.cjs .claude/hooks/sc.cjs tools/srv.js tools/s.sh githooks/pre-commit \
         .claude/skills/myskill/SKILL.md .claude/workflows/w.js .claude/output-styles/o.md \
         .claude/agents/a.md .claude/commands/c.md; do printf 'planted\n' > "$T/b/$f"; done
printf '## Planted\nalways do x\n' > "$T/b/.claude/rules/r.md"
printf '<plist><string>%s/tools/s.sh</string></plist>\n' "$(nat "$T/b")" > "$T/fakehome/Library/LaunchAgents/x.plist"
mkdir -p "$T/fakehome/.claude/plugins"
printf '{"plugins":{"extra@mkt":[{"installPath":"%s"}]}}' "$(nat "$T/plug")" > "$T/fakehome/.claude/plugins/installed_plugins.json"
PLANTED="hook=.claude/hooks/h.cjs
stop-check=.claude/hooks/sc.cjs
mcp=mcp:srv
git-hook=githooks/pre-commit
scheduled=launchd:x.plist
plugin=plugin:extra@mkt
skill=.claude/skills/myskill
workflow=.claude/workflows/w.js
output-style=.claude/output-styles/o.md
agent=.claude/agents/a.md
command=.claude/commands/c.md
rule=.claude/rules/r.md#Planted
script=tools/s.sh"
has() { awk -v c="$2" -v i="$3" '$2==c && $3==i {f=1} END {exit !f}' <<< "$1"; }
listing=$(run --list)
n=0
for c in $(LM --carriers); do
  id=$(printf '%s\n' "$PLANTED" | awk -F= -v c="$c" '$1==c {print substr($0, length(c)+2)}')
  if [[ -z "$id" ]]; then bad "coverage: carrier '$c' has no planted case in this fixture"; continue; fi
  n=$((n + 1))
  has "$listing" "$c" "$id" && ok "coverage-$c-reported" || bad "coverage-$c-reported: $(printf '%s\n' "$listing" | tail -20)"
  grep -v "^    \"$c\": " "$HERE/local-machinery.py" > "$T/neg.py"
  if [[ $(wc -l < "$T/neg.py") -ge $(wc -l < "$HERE/local-machinery.py") ]]; then
    bad "negative-control-$c: carrier line not found in the scanner"; continue
  fi
  neg=$("$PY" "$T/neg.py" --home "$T/fakehome" --repo "$T/b" --today 2026-10-08 --list)
  has "$neg" "$c" "$id" && bad "negative-control-$c: still reported without its carrier" || ok "negative-control-$c-red"
done
carriers=$(LM --carriers)
for c in $(printf '%s\n' "$PLANTED" | cut -d= -f1); do   # the other direction: no planted case orphaned
  grep -qx -- "$c" <<< "$carriers" || bad "coverage: planted carrier '$c' is not in the scanner"
done
summary=$(run | tail -1)
grep -q "^local machinery summary: items=$n .*undeclared=$n" <<< "$summary" && ok "coverage-summary-counts-all-$n" || bad "coverage-summary-counts-all-$n: $summary"
rm -f "$T/fakehome/Library/LaunchAgents/x.plist"

# --- directories Claude Code keeps under ~/.claude/skills ------------------------------------
# Measured 2026-10-10 (Windows instance): `.trash` and the account's synced vendor skills were
# the only items no declaration could carry. But a user's OWN upload also lands in `synced`
# (Mac, 2026-09-30: six with creatorType user) - that one is a local carrier and stays visible.
# Vendor is read from the bucket manifest: `creatorType: anthropic` or `source: anthropic*`.
S="$T/fakehome/.claude/skills"
mkdir -p "$S/.trash/1/t" "$S/mine" "$S/synced/b/vend-src" "$S/synced/b/vend-ct" "$S/synced/b/own" "$S/synced/b/bare" "$S/synced/c/x"
for f in .trash/1/t mine synced/b/vend-src synced/b/vend-ct synced/b/own synced/b/bare synced/c/x; do printf 'x\n' > "$S/$f/SKILL.md"; done
printf '{"skills":[{"skillId":"vend-src","source":"anthropic-example"},{"skillId":"vend-ct","creatorType":"anthropic"},{"skillId":"own","creatorType":"user","source":"anthropic"},{"skillId":"bare"}]}' > "$S/synced/b/manifest.json"
printf 'not json' > "$S/synced/c/manifest.json"
listing=$(run --list)
grep -q '~/.claude/skills/mine' <<< "$listing" && ok "user-skill-in-home-reported" || bad "user-skill-in-home-reported: $listing"
grep -q '\.trash' <<< "$listing" && bad "trash-skipped: $listing" || ok "trash-skipped"
grep -qE 'synced/b/vend-(src|ct)' <<< "$listing" && bad "synced-vendor-skipped: $listing" || ok "synced-vendor-skipped"
grep -q 'synced/b/own' <<< "$listing" && ok "synced-user-upload-reported" || bad "synced-user-upload-reported: $listing"
grep -q 'synced/b/bare' <<< "$listing" && ok "synced-entry-without-field-reported" || bad "synced-entry-without-field-reported: $listing"
grep -q 'synced/c/x' <<< "$listing" && ok "synced-unreadable-manifest-reported" || bad "synced-unreadable-manifest-reported: $listing"
rm -rf "$S"

(( fail )) && { echo "test-local-machinery: FAILED"; exit 1; }
echo "test-local-machinery: all checks passed"
