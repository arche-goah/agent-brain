#!/usr/bin/env bash
# covers: brain-update (the cache provenance discriminator)
#
# The check compares the RECORDED commit against the pinned tag's commit. Those disagree
# in two completely different situations, and until 2026-08-31 both printed FAIL:
#
#   stale record   — the content IS the pinned release; `claude plugin update` simply
#                    does not rewrite gitCommitSha, so every UPDATED plugin failed and
#                    only a freshly installed one passed. Cosmetic.
#   foreign content— the plugin loading right now is NOT what the pin names. Serious.
#
# The discriminator is the version inside the cached plugin.json, against the version the
# tag encodes (this ecosystem guarantees tag == plugin.json version, because
# release-preflight refuses to cut a tag where they differ).
#
# Both directions are asserted, and the FOREIGN case carries the weight: a check that can
# only say "fine" is the thing this whole file exists to prevent.
#
# Run: bash scripts/brain-update-test.sh    Exit 0 = all green.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
ok()  { echo "  OK   $*"; }
bad() { echo "  FAIL $*"; fails=$((fails + 1)); }

# The helper under test is a function inside brain-update.sh; source the file with a
# guard so the script body does not run. Extract instead: pull the function text, which
# keeps this fixture honest about WHAT it tests rather than re-implementing it.
sed -n '/^cached_version() {/,/^}/p' "$HERE/brain-update.sh" > "$TMP/fn.sh"
[ -s "$TMP/fn.sh" ] || { echo "  FAIL cached_version() not found in brain-update.sh"; exit 1; }

# Probe THROUGH the variable, never by naming python3 directly: the Microsoft Store
# ships a `python3` stub that resolves in PATH and does not run, so a bare call is a
# Windows mine and the lint refuses it — rightly, and it caught me here.
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
CFG="$TMP/cfg"
mkdir -p "$CFG/plugins"

make_case() {  # $1 = cache version written into plugin.json
  local cache="$CFG/plugins/cache/demo/$1"
  rm -rf "$CFG/plugins/cache"
  mkdir -p "$cache/.claude-plugin"
  printf '{ "name": "demo", "version": "%s" }\n' "$1" > "$cache/.claude-plugin/plugin.json"
  # Both values travel in the ENVIRONMENT rather than argv — OS-6: a stdin program given
  # a file argument can end up executing that file instead. A .json argument happens to
  # be safe today (no shebang), but relying on that is relying on the input never being
  # a script, and this fixture exists precisely because such assumptions do not hold.
  REC="$CFG/plugins/installed_plugins.json" CACHE="$cache" "$PY" - <<'PY'
import json, os
json.dump({"version": 2, "plugins": {"demo@mk": [
    {"scope": "user", "installPath": os.environ["CACHE"], "version": "x",
     "gitCommitSha": "0000000000000000000000000000000000000000"}]}},
    open(os.environ["REC"], "w", encoding="utf-8"))
PY
}

read_version() { ( . "$TMP/fn.sh"; cached_version demo@mk ) | awk '$1=="user"{print $2}'; }

# --- POSITIVE: the discriminator reads what is actually in the cache ---------------
make_case 1.3.32
got=$(read_version)
if [ "$got" = "1.3.32" ]; then ok "the cached version is read from the install path"
else bad "expected 1.3.32, got '$got'"; fi

# --- NEGATIVE, the load-bearing half: foreign content must NOT read as the pin -----
# A cache whose content says 1.1.2 under a pin of v1.3.32 is the repo-move case the
# provenance check was built for. If the discriminator returned the PIN here instead of
# the CONTENT, a stale-record NOTE would be printed over a real foreign-content defect —
# the check would have been softened into silence rather than sharpened.
make_case 1.1.2
got=$(read_version)
if [ "$got" = "1.1.2" ]; then ok "foreign content reports its own version, not the pin's"
else bad "foreign content masked: got '$got'"; fi

# --- NEGATIVE: an unreadable cache must look unreadable, not like agreement --------
rm -rf "$CFG/plugins/cache"
got=$(read_version)
if [ -z "$got" ]; then ok "a missing cache yields an empty answer, never a match"
else bad "missing cache produced '$got' — absence must look absent"; fi

# --- a project record of ANOTHER project is not this brain's install ---------------
# Measured 2026-10-18: a stale project-scope record of a second project turned this
# brain's run red. Planted: one record for this brain, one for another project.
sed -n '/^recorded_sha() {/,/^}/p' "$HERE/brain-update.sh" > "$TMP/rec.sh"
mkdir -p "$TMP/this" "$TMP/other"
REC="$CFG/plugins/installed_plugins.json" THIS="$TMP/this" OTHER="$TMP/other" "$PY" - <<'PY'
import json, os
json.dump({"version": 2, "plugins": {"demo@mk": [
    {"scope": "project", "projectPath": os.environ["OTHER"], "gitCommitSha": "aaaa"},
    {"scope": "project", "projectPath": os.environ["THIS"], "gitCommitSha": "bbbb"},
    {"scope": "user", "gitCommitSha": "cccc"}]}},
    open(os.environ["REC"], "w", encoding="utf-8"))
PY
got=$( ( . "$TMP/rec.sh"; BRAIN="$TMP/this"; recorded_sha demo@mk ) | tr '\n' ' ')
if [ "$got" = "project bbbb user cccc " ]; then ok "another project's record is left out, this brain's and user's stay"
else bad "expected 'project bbbb user cccc', got '$got'"; fi
got=$( ( . "$TMP/rec.sh"; BRAIN=""; recorded_sha demo@mk ) | wc -l | tr -d ' ')
if [ "$got" = "3" ]; then ok "without a brain root every record is checked (control)"
else bad "control: expected 3 records without a root, got $got"; fi

# --- the three ways a path is NOT a brain must not share one outcome --------------
# Measured 2026-09-02: started from the plugin cache without BRAIN_UPDATE_ROOT, the root
# resolved beside the cache. Everything downstream silently did nothing, git emitted one
# bare `fatal:` from the only call lacking a stderr redirect, and the run still printed
# DONE and exited 0. Each state now names itself and exits non-zero. The probes run the
# real script: the checks sit directly after the cd, so nothing else executes.
UPD="$(cd "$(dirname "$0")" && pwd)/brain-update.sh"
probe_root() { # $1 label, $2 dir, $3 expected substring
  local out rc d="$2"
  command -v cygpath >/dev/null 2>&1 && d="$(cygpath -w "$d")"
  out=$(BRAIN_UPDATE_ROOT="$d" bash "$UPD" 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then bad "$1: exited 0 — a non-brain must never report success"; return; fi
  case "$out" in
    *DONE*) bad "$1: printed DONE over a FAIL"; return ;;
  esac
  case "$out" in
    *"$3"*) ok "$1" ;;
    *) bad "$1: wrong message: $(printf %s "$out" | head -1)" ;;
  esac
}

NB=$(mktemp -d)                       # not a git repository at all
probe_root "no brain at the path names itself" "$NB" "not a git repository"

NC=$(mktemp -d)                       # a git repo, but no core/
git -c init.defaultBranch=main init -q "$NC"
probe_root "a brain without core/ names itself" "$NC" "has no core/ directory"

NU=$(mktemp -d)                       # a git repo with an uninitialised core/
git -c init.defaultBranch=main init -q "$NU"; mkdir -p "$NU/core"
probe_root "an uninitialised core/ names itself" "$NU" "not a git repository — submodule not initialised"

rm -rf "$NB" "$NC" "$NU"

# --- core/ moves only on a fresh pin, and never backwards --------------------------
# The real script runs against a fake brain: core/ committed as a submodule with a
# .gitmodules entry, a `claude` stub (STUB_MKT_FAIL names the marketplaces whose refresh
# fails, STUB_PLUG_FAIL=1 fails `claude plugin update`), `gh` stubbed out (nothing is
# pushed). A GitHub URL a case names is redirected to the local origin through git's own
# environment config, so no case touches the network.
SB=$(mktemp -d); ORIG="$SB/origin.git"; STUB="$SB/bin"
git -c init.defaultBranch=main init -q "$SB/src"
for v in 1.0.0 2.0.0; do
  git -C "$SB/src" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$v"
  git -C "$SB/src" tag "v$v"
done
git clone -q --bare "$SB/src" "$ORIG"
mkdir -p "$STUB"
cat > "$STUB/claude" <<'SH'
#!/bin/sh
if [ "$1 $2 $3" = "plugin marketplace update" ]; then
  case " ${STUB_MKT_FAIL:-} " in *" $4 "*) exit 1 ;; esac
  exit 0
fi
if [ "$1 $2" = "plugin update" ] && [ -n "${STUB_PLUG_FAIL:-}" ]; then exit 1; fi
exit 0
SH
printf '#!/bin/sh\nexit 1\n' > "$STUB/gh"; chmod +x "$STUB/claude" "$STUB/gh"
V1=$(git -C "$SB/src" rev-parse v1.0.0); V2=$(git -C "$SB/src" rev-parse v2.0.0)

mk_brain() { # $1 name, $2 committed core tag, $3 installed plugin version, $4 marketplaces,
             # $5 repo the cached marketplace entry names ("" = no marketplace.json)
  local B="$SB/$1" C="$SB/$1.cfg" mk="" sep="" m
  git -c init.defaultBranch=main init -q "$B"
  git clone -q "$ORIG" "$B/core"; git -C "$B/core" checkout -q "tags/$2"
  printf '[submodule "core"]\n\tpath = core\n\turl = https://github.com/arche-goah/agent-brain.git\n' > "$B/.gitmodules"
  git -C "$B" add .gitmodules core 2>/dev/null
  git -C "$B" -c user.name=t -c user.email=t@t commit -q -m base
  mkdir -p "$B/.claude" "$C/plugins"
  for m in $4; do mk="$mk$sep\"$m\":{}"; sep=","; done
  printf '{"extraKnownMarketplaces":{%s},"enabledPlugins":{"brain-core@mk":true}}\n' "$mk" > "$B/.claude/settings.json"
  printf '{"version":2,"plugins":{"brain-core@mk":[{"scope":"project","version":"%s"}]}}\n' "$3" > "$C/plugins/installed_plugins.json"
  if [ -n "$5" ]; then
    mkdir -p "$C/plugins/marketplaces/mk/.claude-plugin"
    printf '{"plugins":[{"name":"brain-core","source":{"source":"github","repo":"%s","ref":"v1.0.0"}}]}\n' "$5" \
      > "$C/plugins/marketplaces/mk/.claude-plugin/marketplace.json"
  fi
}
run_brain() { # $1 name, $2 the GitHub repo redirected to the local origin -> the run's output
  local d="$SB/$1"; command -v cygpath >/dev/null 2>&1 && d="$(cygpath -w "$d")"
  PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$SB/$1.cfg" BRAIN_UPDATE_ROOT="$d" GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0="url.$ORIG.insteadOf" GIT_CONFIG_VALUE_0="https://github.com/${2:-none/none}.git" bash "$UPD" 2>&1
}
commits() { git -C "$SB/$1" rev-list --count HEAD; }

# 1. every refresh fails (measured 2026-10-22: the cached plugin said 1.0.0 while the brain
#    sat on v2.0.0 - the run checked out the OLD tag and pushed it).
mk_brain stale v2.0.0 1.0.0 "mk" ""
out=$(STUB_MKT_FAIL="mk" STUB_PLUG_FAIL=1 run_brain stale)
if [ "$(git -C "$SB/stale/core" rev-parse HEAD)" != "$V2" ]; then
  bad "stale marketplace: core/ moved off v2.0.0 to the cached pin"
else case "$out" in
  *"core NOT moved"*"marketplace mk was not refreshed"*) ok "stale marketplace: core/ stays, the FAIL line names the marketplace" ;;
  *) bad "stale marketplace: core/ stayed, but no FAIL naming it: $(printf %s "$out" | grep -a -m1 'core NOT')" ;;
esac; fi

# 2. the cached entry names ANOTHER repo (review of #76, gap 1): nothing re-pointed, nothing committed.
mk_brain repoint v2.0.0 1.0.0 "mk" "old-owner/old-repo"
n0=$(commits repoint); o0=$(git -C "$SB/repoint/core" remote get-url origin)   # (git keeps a local path in its own form)
out=$(STUB_MKT_FAIL="mk" run_brain repoint old-owner/old-repo)
decl=$(git -C "$SB/repoint" config -f .gitmodules submodule.core.url)
if [ "$decl" != "https://github.com/arche-goah/agent-brain.git" ] || [ "$(git -C "$SB/repoint/core" remote get-url origin)" != "$o0" ]; then
  bad "stale pin re-pointed the core repo: .gitmodules '$decl'"
elif [ "$(commits repoint)" != "$n0" ]; then
  bad "stale pin: the run committed something ($(git -C "$SB/repoint" log -1 --format=%s))"
else case "$out" in
  *"NOT re-pointed to old-owner/old-repo"*) ok "stale pin naming another repo: origin and .gitmodules untouched, nothing committed" ;;
  *) bad "stale pin: untouched, but the run does not say so" ;;
esac; fi

# 3. refreshed marketplace, failed plugin update, entry without a ref (gap 2a): the installed
#    version is stale as well - no move.
mk_brain plugfail v2.0.0 1.0.0 "mk" ""
out=$(STUB_PLUG_FAIL=1 run_brain plugfail)
if [ "$(git -C "$SB/plugfail/core" rev-parse HEAD)" != "$V2" ]; then
  bad "failed plugin update: core/ moved v2.0.0 -> v1.0.0"
else case "$out" in
  *"plugin brain-core@mk was not updated"*) ok "failed plugin update: core/ stays, the FAIL line names the plugin" ;;
  *) bad "failed plugin update: core/ stayed, but no FAIL naming it" ;;
esac; fi

# 4. every refresh fine, but the target is OLDER than the committed core (gap 2b, the direction
#    check): whatever named the old tag, no automatic downgrade.
mk_brain older v2.0.0 1.0.0 "mk" ""
out=$(run_brain older)
if [ "$(git -C "$SB/older/core" rev-parse HEAD)" != "$V2" ]; then
  bad "downgrade: core/ moved v2.0.0 -> v1.0.0 on a fresh run"
else case "$out" in
  *"older than the core this brain committed"*"roll back"*) ok "downgrade refused with the rollback command" ;;
  *) bad "downgrade: core/ stayed, but no FAIL line with the rollback" ;;
esac; fi

# 5. an UNRELATED marketplace fails, the core's own refreshed (gap 3): the core still moves forward.
mk_brain other v1.0.0 2.0.0 "mk other" ""
out=$(STUB_MKT_FAIL="other" run_brain other)
if [ "$(git -C "$SB/other/core" rev-parse HEAD)" != "$V2" ]; then
  bad "an unrelated failed marketplace blocked the core move: $(printf %s "$out" | grep -a -m1 'core')"
else case "$out" in
  *"core NOT moved"*) bad "core moved, but a FAIL line still blamed a marketplace" ;;
  *"WARN marketplace other not refreshed"*) ok "an unrelated failed marketplace does not block core/ (v1.0.0 -> v2.0.0)" ;;
  *) bad "core moved, but the failed marketplace was not reported" ;;
esac; fi
rm -rf "$SB"

echo
if (( fails )); then echo "brain-update-test: $fails FAILURE(S)"; exit 1; fi
echo "brain-update-test: all 13 checks passed"
