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

echo
if (( fails )); then echo "brain-update-test: $fails FAILURE(S)"; exit 1; fi
echo "brain-update-test: all 6 checks passed"
