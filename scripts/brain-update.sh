#!/usr/bin/env bash
# brain-update.sh — ONE command that brings a brain to the released state.
#
# Operator order 2026-08-13: the human never has to know which channel carries
# what (marketplace pin, plugin cache, core/ submodule, ecosystem record) — they
# say "update", this runs, at the end everything consumes the same released tag.
#
# What it does, in order, all idempotent:
#   1. refresh every marketplace named in the brain's settings
#   2. update every ENABLED plugin of those marketplaces (claude CLI channel),
#      then verify each plugin cache's PROVENANCE (commit SHA vs the pinned source)
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

# Resolve the Python interpreter: the python.org installer on Windows ships ONLY
# `python`, and the Microsoft Store ships a `python3` STUB that resolves in PATH but
# does not run — so probe by RUNNING it, never with `command -v` (measured 2026-08-14:
# a colleague brain had no working `python3`, every reader below returned empty and
# brain-update.sh printed DONE without having done anything).
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python

# Brain root = two levels above this script (core/scripts/ -> brain).
# BRAIN_UPDATE_ROOT overrides it (tests, running a checkout copy against a brain).
BRAIN="${BRAIN_UPDATE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$BRAIN" || { echo "FAIL cannot cd to brain root"; exit 1; }
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
changed=0; plugin_moved=0; failed=0

# -- settings readers (project + user merged) ---------------------------------
# Every reader ends in `tr -d '\r'`: Windows Python writes CRLF to pipes, and MSYS
# `$(...)` only strips the TRAILING CR — in a multi-line list every item except the
# last keeps its `\r` through word splitting, so plugin-id lookups fail silently
# (measured 2026-08-13, Windows brain: `brain-core@arche-goah` reported "not
# installed" while installed at 1.9.0; on a stale brain the update would no-op and
# still print DONE). Same class effect-check guards with `pver=${pver%$'\r'}`.
marketplaces() {
  "$PY" -c '
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
  "$PY" -c '
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
  "$PY" -c '
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

recorded_sha() { # $1 = plugin id -> one "scope sha" line PER install record.
  # A plugin can be installed at several scopes (user + project) and the records
  # are independent — reading only the first entry lets a stale record mask a
  # healed one and vice versa (measured 2026-08-13: a fresh user-scope reinstall
  # recorded the correct sha, but a stale project-scope duplicate sat at index 0
  # and kept the check red; the reverse masking is just as possible).
  "$PY" -c '
import json, os, sys
try:
    with open(os.path.join(sys.argv[1], "plugins", "installed_plugins.json"), encoding="utf-8") as f:
        d = json.load(f)
    for x in (d.get("plugins") or {}).get(sys.argv[2]) or []:
        print((x.get("scope") or "?") + " " + x.get("gitCommitSha", ""))
except Exception:
    pass
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
#    Convention: the core plugin and the core/ submodule are the SAME repo, same
#    tag — and the MARKETPLACE PIN is the single source of truth for both: its
#    entry names repo AND ref. The submodule is aligned to the pinned repo BEFORE
#    the tag resolves, on EVERY layer that names the repo: the submodule's own
#    origin remote, the superproject config, and the .gitmodules DECLARATION —
#    a fresh clone reads only the declaration, so a live-only fix leaves every
#    future clone resolving the old repo where the pinned commit does not exist
#    (measured 2026-08-13 right after the public fresh cut). Without a readable
#    pin entry: the installed version names the tag (plugin 1.9.0 <=> tag
#    v1.9.0), nothing is re-pointed.
norm_url() { printf '%s' "$1" | sed -e 's#^git@github\.com:#https://github.com/#' -e 's#\.git$##'; }
marketplace_pin() { # $1 = marketplace name, $2 = plugin name -> "repo ref" or ""
  "$PY" -c '
import json, os, sys
p = os.path.join(sys.argv[1], "plugins", "marketplaces", sys.argv[2],
                 ".claude-plugin", "marketplace.json")
try:
    with open(p, encoding="utf-8") as f:
        d = json.load(f)
    for e in d.get("plugins") or []:
        if e.get("name") == sys.argv[3]:
            s = e.get("source") or {}
            if s.get("source") == "github" and s.get("repo"):
                print(s.get("repo") + " " + s.get("ref", ""))
            break
except Exception:
    pass
' "$CFG" "$1" "$2" | tr -d '\r'
}

# 2b) cache provenance (sits here because it reuses marketplace_pin above).
#     The plugin cache is keyed by NAME+VERSION, not by source. After a repo move
#     (the pin now names a different repo that carries the same version string)
#     `claude plugin update/install` no-op on "already at X" and keep FOREIGN
#     content under the right version name — measured 2026-08-13: a brain-core
#     1.0.1 cache from the pre-move repo (content: its release 1.1.2) survived
#     the pin move; output style dead, stale skill channel, while submodule,
#     marketplace checkout and remote tags all verified clean. The version string
#     is a NAME; only the commit SHA ties the cache to the pinned source.
#     The record can also be wrong the OTHER way (measured 2026-08-13, Windows
#     brain, twice): cache content byte-identical to the pinned tag while
#     gitCommitSha still names an old commit (in-place update did not refresh the
#     record; one cache even recorded a commit whose plugin.json says 1.1.2 under
#     a 1.1.4 cache). A mismatch therefore proves ONLY that the record does not
#     describe the pin — foreign content and stale record are indistinguishable
#     from here. The remediation is identical (reinstall rewrites record AND
#     content), so the check stays; the message must not claim more than that.
for p in $(enabled_plugins); do
  recs=$(recorded_sha "$p")
  [ -n "$recs" ] || continue       # not installed: nothing to verify against
  pin=$(marketplace_pin "${p#*@}" "${p%@*}")
  pin_repo="${pin%% *}"
  pin_ref="${pin#* }"
  if [ -z "$pin_repo" ] || [ -z "$pin_ref" ] || [ "$pin_ref" = "$pin" ]; then
    continue                       # no github pin with a ref: no source of truth to compare
  fi
  # Annotated tags peel to the commit on the ^{} line; lightweight tags only have
  # the plain line. installed_plugins.json records the COMMIT sha, so prefer peeled.
  want_sha=$(git ls-remote "https://github.com/$pin_repo.git" "refs/tags/$pin_ref" "refs/tags/$pin_ref^{}" 2>/dev/null \
    | awk '{ if ($2 ~ /\^\{\}$/) p=$1; else t=$1 } END { if (p) print p; else if (t) print t }')
  if [ -z "$want_sha" ]; then
    echo "WARN plugin $p provenance unverified (cannot resolve $pin_repo@$pin_ref — offline?)"
    continue
  fi
  # EVERY install record is checked — scopes are independent (see recorded_sha).
  while read -r scope have_sha; do
    [ -n "$have_sha" ] || continue # a pre-SHA record: nothing to verify against
    if [ "$have_sha" = "$want_sha" ]; then
      echo "OK   plugin $p ($scope) cache matches its pin ($pin_repo@$pin_ref)"
    else
      echo "FAIL plugin $p ($scope) cache provenance mismatch — foreign content OR stale install record:"
      echo "     installed commit ${have_sha:0:12} != pinned ${want_sha:0:12} ($pin_repo@$pin_ref)"
      echo "     fix (either way): claude plugin uninstall $p --scope $scope  &&  claude plugin install $p  — then restart Claude Code"
      failed=1
    fi
  done <<< "$recs"
done

core_plugin=$(enabled_plugins | grep -E '^brain-core@' | head -1 || true)
if [ -n "$core_plugin" ] && [ -d core ] && git -C core rev-parse --git-dir >/dev/null 2>&1; then
  ver=$(installed_version "$core_plugin")
  if [ -n "$ver" ]; then
    tag="v$ver"
    pin=$(marketplace_pin "${core_plugin#*@}" "${core_plugin%@*}")
    pin_repo="${pin%% *}"
    pin_ref="${pin#* }"
    if [ -n "$pin_repo" ]; then
      [ -n "$pin_ref" ] && [ "$pin_ref" != "$pin" ] && tag="$pin_ref"
      want_url="https://github.com/$pin_repo.git"
      cur_url=$(git -C core remote get-url origin 2>/dev/null || echo "")
      if [ -n "$cur_url" ] && [ "$(norm_url "$cur_url")" != "$(norm_url "$want_url")" ]; then
        git -C core remote set-url origin "$want_url"
        echo "OK   core origin -> $pin_repo (follows the marketplace pin)"
        changed=1
      fi
      decl=$(git config -f .gitmodules submodule.core.url 2>/dev/null || echo "")
      if [ -n "$decl" ] && [ "$(norm_url "$decl")" != "$(norm_url "$want_url")" ]; then
        git config -f .gitmodules submodule.core.url "$want_url"
        git submodule sync -- core >/dev/null 2>&1
        echo "OK   .gitmodules core url -> $pin_repo (fresh clones resolve the pinned repo)"
        changed=1
      fi
    fi
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
      failed=1
    fi
  else
    echo "WARN $core_plugin not installed — core/ left untouched"
  fi
fi

# 4) ecosystem record
if [ -f core/scripts/ecosystem-sync.py ] && [ -f config/ecosystem.json ]; then
  "$PY" core/scripts/ecosystem-sync.py --write >/dev/null 2>&1 \
    && echo "OK   ecosystem record refreshed" \
    || echo "WARN ecosystem-sync failed (non-fatal)"
fi

# 5) commit + push (own brain repo only — that is where this script lives)
if ! git diff --quiet -- core config/ecosystem.json .gitmodules 2>/dev/null; then
  git add core config/ecosystem.json .gitmodules 2>/dev/null
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
# A FAIL line must reach the exit code — a scheduler or one-word update that
# prints DONE and exits 0 over a red line is the "false green" class again.
if [ "$failed" -eq 1 ]; then
  echo "DONE — WITH FAILURES: see FAIL lines above; the brain is NOT fully on the released state."
  [ "$plugin_moved" -eq 1 ] && echo "(a plugin still changed on disk — restart Claude Code regardless)"
  exit 1
fi
if [ "$plugin_moved" -eq 1 ]; then
  echo "DONE — RESTART REQUIRED: close Claude Code and start it again (new terminal on"
  echo "Windows); plugin skills, hooks and the output style only load on the next start."
elif [ "$changed" -eq 1 ]; then
  echo "DONE — no restart needed (no plugin content changed)."
else
  echo "DONE — already up to date."
fi
