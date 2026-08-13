#!/usr/bin/env bash
# brain-update.sh — ONE command that brings a brain to the released state.
#
# Operator order 2026-08-13: the human never has to know which channel carries
# what (marketplace pin, plugin cache, core/ submodule, ecosystem record) — they
# say "update", this runs, at the end everything consumes the same released tag.
#
# What it does, in order, all idempotent:
#   1. refresh every marketplace named in the brain's settings
#   2. update every ENABLED plugin of those marketplaces (claude CLI channel)
#   3. put the core/ submodule on the tag the plugin channel resolved
#      (the marketplace pin — both channels ship the same repo, same tag)
#   4. refresh config/ecosystem.json if the brain carries one
#   5. commit the moved pin in the brain repo; push only if the repo is private
#      (push rule 2026-08-13: own private brain main is free, anything else is not)
#   6. say whether a Claude Code restart is needed (plugin changes only apply then)
#
# Safe to run twice: a current brain prints "already up to date" and changes nothing.
# Needs: git, python3, claude CLI, gh (push visibility check only — skipped without it).
set -uo pipefail

# Brain root = two levels above this script (core/scripts/ -> brain).
# BRAIN_UPDATE_ROOT overrides it (tests, running a checkout copy against a brain).
BRAIN="${BRAIN_UPDATE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$BRAIN" || { echo "FAIL cannot cd to brain root"; exit 1; }
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
changed=0; plugin_moved=0

# -- settings readers (project + user merged) ---------------------------------
# Every reader ends in `tr -d '\r'`: Windows Python writes CRLF to pipes, and MSYS
# `$(...)` only strips the TRAILING CR — in a multi-line list every item except the
# last keeps its `\r` through word splitting, so plugin-id lookups fail silently
# (measured 2026-08-13, Windows brain: `brain-core@arche-goah` reported "not
# installed" while installed at 1.9.0; on a stale brain the update would no-op and
# still print DONE). Same class effect-check guards with `pver=${pver%$'\r'}`.
marketplaces() {
  python3 -c '
import json, os, sys
def load(p):
    try:
        with open(p, encoding="utf-8") as f: return json.load(f)
    except Exception: return {}
cfg = sys.argv[1]
seen = set()
for s in (load(".claude/settings.json"), load(os.path.join(cfg, "settings.json"))):
    for name in (s.get("extraKnownMarketplaces") or {}):
        if name not in seen:
            seen.add(name); print(name)
' "$CFG" | tr -d '\r'
}

enabled_plugins() {
  python3 -c '
import json, os, sys
def load(p):
    try:
        with open(p, encoding="utf-8") as f: return json.load(f)
    except Exception: return {}
cfg = sys.argv[1]
seen = set()
for s in (load(".claude/settings.json"), load(os.path.join(cfg, "settings.json"))):
    for k, v in (s.get("enabledPlugins") or {}).items():
        if v and k not in seen:
            seen.add(k); print(k)
' "$CFG" | tr -d '\r'
}

installed_version() { # $1 = plugin id (name@marketplace)
  python3 -c '
import json, os, sys
try:
    with open(os.path.join(sys.argv[1], "plugins", "installed_plugins.json"), encoding="utf-8") as f:
        d = json.load(f)
    e = (d.get("plugins") or {}).get(sys.argv[2]) or []
    print(e[0].get("version", "") if e else "")
except Exception:
    print("")
' "$CFG" "$1" | tr -d '\r'
}

echo "=== brain-update: $BRAIN ==="

# 1) marketplaces
for m in $(marketplaces); do
  if claude plugin marketplace update "$m" >/dev/null 2>&1; then
    echo "OK   marketplace $m refreshed"
  else
    echo "WARN marketplace $m not refreshed (offline? CLI missing?) — continuing with cached state"
  fi
done

# 2) plugins
for p in $(enabled_plugins); do
  before=$(installed_version "$p")
  out=$(claude plugin update "$p" 2>&1)
  after=$(installed_version "$p")
  if [ -n "$after" ] && [ "$after" != "$before" ]; then
    echo "OK   plugin $p ${before:-?} -> $after"
    plugin_moved=1; changed=1
  elif printf '%s' "$out" | grep -qi "updated"; then
    echo "OK   plugin $p updated (version unchanged in record)"
    plugin_moved=1; changed=1
  else
    echo "OK   plugin $p already current (${after:-not installed})"
  fi
done

# 3) core/ submodule onto the same released tag the plugin channel resolved.
#    Convention: the core plugin and the core/ submodule are the SAME repo; the
#    plugin's installed version names the tag (plugin 1.9.0 <=> tag v1.9.0).
core_plugin=$(enabled_plugins | grep -E '^brain-core@' | head -1 || true)
if [ -n "$core_plugin" ] && [ -d core ] && git -C core rev-parse --git-dir >/dev/null 2>&1; then
  ver=$(installed_version "$core_plugin")
  if [ -n "$ver" ]; then
    tag="v$ver"
    cur=$(git -C core describe --tags 2>/dev/null || echo none)
    # --force on the tag fetch, and the local tag is verified against the remote:
    # a plain fetch refuses to move an existing tag, so after an upstream history
    # rewrite the brain would silently keep checking out the OLD commit under the
    # RIGHT name — describe matches the pin and nothing ever heals. Verify-then-
    # checkout closes that: the remote SHA is the truth, the local name is not.
    git -C core fetch -q --tags --force 2>/dev/null
    want=$(git -C core ls-remote origin "refs/tags/$tag" 2>/dev/null | awk 'NR==1{print $1}')
    have=$(git -C core rev-parse "tags/$tag^{commit}" 2>/dev/null || echo none)
    if [ -n "$want" ] && [ "$have" != "$want" ]; then
      git -C core fetch -q --force origin "+refs/tags/$tag:refs/tags/$tag" 2>/dev/null
      have=$(git -C core rev-parse "tags/$tag^{commit}" 2>/dev/null || echo none)
    fi
    at=$(git -C core rev-parse HEAD 2>/dev/null || echo none)
    if [ "$at" = "$have" ] && [ "$cur" = "$tag" ] && { [ -z "$want" ] || [ "$have" = "$want" ]; }; then
      echo "OK   core already on $tag"
    elif git -C core checkout -q "tags/$tag" 2>/dev/null; then
      echo "OK   core $cur -> $tag"
      changed=1
    else
      echo "FAIL core could not move to $tag (network? tag missing?) — still on $cur"
    fi
  else
    echo "WARN $core_plugin not installed — core/ left untouched"
  fi
fi

# 4) ecosystem record
if [ -f core/scripts/ecosystem-sync.py ] && [ -f config/ecosystem.json ]; then
  python3 core/scripts/ecosystem-sync.py --write >/dev/null 2>&1 \
    && echo "OK   ecosystem record refreshed" \
    || echo "WARN ecosystem-sync failed (non-fatal)"
fi

# 5) commit + push (own brain repo only — that is where this script lives)
if ! git diff --quiet -- core config/ecosystem.json 2>/dev/null; then
  git add core config/ecosystem.json 2>/dev/null
  if git commit -q -m "chore(core): brain-update to the released state"; then
    echo "OK   pin committed"
    vis=$(gh repo view --json visibility --jq .visibility 2>/dev/null || echo unknown)
    if [ "$vis" = "PRIVATE" ]; then
      git push -q 2>/dev/null && echo "OK   pushed (own private brain — free per push rule 2026-08-13)" \
        || echo "WARN push failed (offline?) — commit is local, push later"
    else
      echo "NOTE not pushed (repo visibility: $vis — only a PRIVATE own brain pushes freely)"
    fi
  fi
fi

echo
if [ "$plugin_moved" -eq 1 ]; then
  echo "DONE — RESTART REQUIRED: close Claude Code and start it again (new terminal on"
  echo "Windows); plugin skills, hooks and the output style only load on the next start."
elif [ "$changed" -eq 1 ]; then
  echo "DONE — no restart needed (no plugin content changed)."
else
  echo "DONE — already up to date."
fi
