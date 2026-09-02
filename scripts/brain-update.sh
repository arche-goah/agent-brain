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

# WHERE AM I? Three states that must not share one outcome (measured 2026-09-02): run
# from the plugin cache without BRAIN_UPDATE_ROOT, the root resolves two levels above the
# script — beside the cache, not into a brain. Every later step then silently did nothing,
# git printed one bare `fatal:` from the only call without a stderr redirect, and the run
# still ended in DONE with exit 0. A cd that succeeds proves the directory exists, nothing
# more; each of the three ways this is not a brain now names itself and exits.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "FAIL no brain at $BRAIN — that path is not a git repository."
  echo "     If you started this script from the plugin cache or a bare checkout, point it"
  echo "     at the brain: BRAIN_UPDATE_ROOT=<brain-root> bash <this script>"
  exit 1
fi
if [ ! -d core ]; then
  echo "FAIL brain at $BRAIN has no core/ directory — there is no submodule to align."
  exit 1
fi
# `git -C core rev-parse --git-dir` is NOT the test here: git walks upwards, so inside a
# brain an EMPTY core/ answers with the superproject and the probe reports a healthy
# submodule. An initialised submodule has its own core/.git (file or directory); that is
# the thing being asked about.
if [ ! -e core/.git ]; then
  echo "FAIL core/ at $BRAIN exists but is not a git repository — submodule not initialised."
  echo "     git -C \"$BRAIN\" submodule update --init core"
  exit 1
fi
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

# The version string INSIDE the cached plugin, read from the cache directory the record
# names. This is the discriminator the provenance check lacked: the recorded sha and the
# cached content are two independent facts, and only one of them describes what actually
# loads. Empty when the path or the file is unreadable — an absent answer must look
# absent, never like agreement.
cached_version() {   # $1 = plugin@marketplace
  "$PY" -c '
import json, os, sys
try:
    with open(os.path.join(sys.argv[1], "plugins", "installed_plugins.json"), encoding="utf-8") as f:
        d = json.load(f)
    for x in (d.get("plugins") or {}).get(sys.argv[2]) or []:
        p = os.path.join(x.get("installPath", ""), ".claude-plugin", "plugin.json")
        try:
            with open(p, encoding="utf-8") as g:
                print((x.get("scope") or "?") + " " + (json.load(g).get("version") or ""))
        except Exception:
            print((x.get("scope") or "?") + " ")
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
      # The two states are NOT indistinguishable any more, and telling them apart is
      # the whole value: a stale record is cosmetic, foreign content means the plugin
      # loading right now is not the one the pin names. The discriminator is the
      # version inside the cache, against the version the pin's tag encodes — this
      # ecosystem guarantees tag == plugin.json version, because release-preflight
      # refuses to cut a tag where they differ. Measured 2026-08-31 on two consecutive
      # releases: content 1.3.31 then 1.3.32, both correct, while the record kept the
      # sha of the 1.3.25 install — `claude plugin update` does not rewrite that field,
      # so the check failed on every UPDATED plugin and only ever passed on a freshly
      # installed one.
      have_ver=$(cached_version "$p" | awk -v s="$scope" '$1 == s { print $2 }')
      want_ver="${pin_ref#v}"
      if [ -n "$have_ver" ] && [ "$have_ver" = "$want_ver" ]; then
        echo "NOTE plugin $p ($scope) install record is stale, content is the pinned release:"
        echo "     cached plugin.json says $have_ver = $pin_ref; recorded commit ${have_sha:0:12} is older"
        echo "     harmless — the record is refreshed by a reinstall, not by an update"
      else
        echo "FAIL plugin $p ($scope) cache provenance mismatch — content is NOT the pinned release:"
        echo "     installed commit ${have_sha:0:12} != pinned ${want_sha:0:12} ($pin_repo@$pin_ref)"
        echo "     cached version '${have_ver:-unreadable}' vs pinned '$want_ver'"
        echo "     fix: claude plugin uninstall $p --scope $scope  &&  claude plugin install $p  — then restart Claude Code"
        failed=1
      fi
    fi
  done <<< "$recs"
done

# The core channel is whichever of brain-core / brain-core-next is ENABLED — both
# ship the same repo, and the marketplace forbids running both at once. Binding this
# to the literal name `brain-core` made the submodule step SKIP SILENTLY on a machine
# that switched to the test channel, while "DONE" still printed (measured 2026-09-02,
# first beta step of v1.3.33: plugin on 1.3.33, submodule left on v1.3.32). If both
# channels are enabled, that misconfiguration is reported instead of picking one.
core_plugin=""; core_channels=0
for _p in $(enabled_plugins); do
  case "$_p" in
    brain-core@*|brain-core-next@*) core_plugin="$_p"; core_channels=$((core_channels + 1)) ;;
  esac
done
if [ "$core_channels" -gt 1 ]; then
  echo "FAIL both brain-core AND brain-core-next are enabled — they ship the same skills and collide; disable one, then re-run"
  exit 1
fi
if [ -z "$core_plugin" ] && [ -d core ]; then
  echo "WARN no core channel plugin enabled (brain-core / brain-core-next) — core/ submodule NOT aligned this run"
fi
if [ -n "$core_plugin" ] && [ -d core ] && [ -e core/.git ]; then
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
    # ls-remote returns the TAG OBJECT sha for an annotated tag, while `have` below is a
    # COMMIT sha — comparing them can never be equal, so the verify-then-checkout guard
    # described above never held and every run took the repair path and reported a move
    # that had not happened (measured 2026-09-02: "core v1.3.34 -> v1.3.34" on a brain
    # already sitting on that tag). Ask for the dereferenced ref as well and prefer it;
    # a lightweight tag has no ^{} line and falls back to the plain one.
    want=$(git -C core ls-remote origin "refs/tags/$tag" "refs/tags/$tag^{}" 2>/dev/null | awk '$2 ~ /\^\{\}$/ {deref=$1} $2 !~ /\^\{\}$/ {plain=$1} END {print (deref ? deref : plain)}')
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

# 4b) invariant register — a fixed step of every release catch-up (operator order
# 2026-08-19): a class needs a place where it stays open, and a brain without the
# register gets the class-discipline rules as prose only — exactly the form that
# gets pattern-matched instead of understood. Created once from the template,
# never overwritten (the register is instance history).
if [ ! -f docs/maintenance/invariants.md ] && [ -f core/templates/invariants.md ]; then
  mkdir -p docs/maintenance
  cp core/templates/invariants.md docs/maintenance/invariants.md \
    && echo "OK   invariant register created (docs/maintenance/invariants.md, from core template — seed your first class)" \
    || echo "WARN could not create the invariant register"
fi

# 4c) hook coverage — a template hook reaches existing brains only as a CHANGELOG
# sentence, so a release can leave a helper consumed but wired nowhere (measured
# 2026-08-19, Windows instance: class-gate.cjs shipped in v1.3.12, ran never).
# Reported, never edited: settings.json is operator territory. The bootup repeats
# this as a !! line every session until it is fixed.
if [ -f core/scripts/hook-coverage.py ]; then
  hc=$("$PY" core/scripts/hook-coverage.py . 2>/dev/null)
  if [ -n "$hc" ]; then
    echo "WARN hooks from the core template are not wired in this brain:"
    printf '%s\n' "$hc" | sed 's/^/     /'
    echo "     add the line(s) to .claude/settings.json by hand (operator edit; template: core/templates/settings.json), then restart Claude Code"
  fi
fi

# 5) commit + push (own brain repo only — that is where this script lives)
# `git diff --quiet` answers 0 = clean, 1 = differences, >1 = it could not tell (128 in a
# non-repo). Testing it with `if !` collapses the last two into "there are changes", and
# the failure then surfaced only as a bare `fatal:` from git commit — the one call here
# without a stderr redirect. The exit code is read explicitly so "cannot tell" reaches the
# FAIL path instead of the commit path.
git diff --quiet -- core config/ecosystem.json .gitmodules 2>/dev/null; pin_dirty=$?
if [ "$pin_dirty" -gt 1 ]; then
  echo "FAIL cannot tell whether the pin moved (git diff exit $pin_dirty) — nothing committed"
  failed=1
elif [ "$pin_dirty" -eq 1 ]; then
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
