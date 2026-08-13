#!/usr/bin/env bash
# suite-install.sh — ONE command that puts a tool suite at its released state.
#
# Operator order 2026-08-13: colleagues must be able to fetch a suite the moment
# it is released, without knowing the machinery. Released = a version TAG on the
# suite repo — this script never checks out main: an untagged state is not
# released, and consuming it would silently run unreviewed code.
#
# Usage:
#   suite-install.sh <suite> [tag]   # install or update one suite (default: newest v* tag)
#   suite-install.sh --all           # update every suite the brain's ecosystem records
#
# What it does, in order, all idempotent:
#   1. resolve the suite's path + remote — from config/ecosystem.json when the
#      brain records it (kind "suite"), else ~/Projects/<suite> on the default org
#   2. clone when missing, fetch when present; local changes are a HARD STOP
#      (this script updates consumers, it never eats a developer checkout)
#   3. check out the requested tag, or the newest v* tag
#   4. surface the suite's requires_core against the running core contract
#   5. refresh the brain's ecosystem record (when the brain carries one)
#   6. point at the suite's own wiring notes — the .mcp.json entry and skill
#      symlinks stay a documented hand step ON PURPOSE: a launcher carries
#      operator-specific addresses and credential names, so no shared script
#      writes it for you
#
# Safe to run twice: a current suite prints "already at <tag>" and changes nothing.
# Needs: git, python3. SUITE_ORG / SUITE_BASE_DIR override the defaults.
set -uo pipefail

BRAIN="${BRAIN_UPDATE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
ORG="${SUITE_ORG:-arche-goah}"
BASE="${SUITE_BASE_DIR:-$HOME/Projects}"
ECO="$BRAIN/config/ecosystem.json"

usage() { echo "usage: suite-install.sh <suite>|--all [tag]" >&2; exit 2; }
[ $# -ge 1 ] || usage

# -- ecosystem readers (best effort — a fresh colleague brain may not record suites yet)
eco_field() {  # eco_field <suite> <field>
  [ -f "$ECO" ] || return 1
  python3 - "$ECO" "$1" "$2" <<'PY' 2>/dev/null
import json, sys
eco, suite, field = sys.argv[1:4]
e = json.load(open(eco)).get("repos", {}).get(suite)
if not e or e.get("kind") != "suite" or not e.get(field): sys.exit(1)
print(e[field])
PY
}

eco_suites() {
  [ -f "$ECO" ] || return 0
  python3 - "$ECO" <<'PY' 2>/dev/null
import json, sys
for name, e in json.load(open(sys.argv[1])).get("repos", {}).items():
    if isinstance(e, dict) and e.get("kind") == "suite": print(name)
PY
}

install_one() {  # install_one <suite> [tag]
  local suite="$1" tag="${2:-}" dir remote just_cloned=0
  dir="$(eco_field "$suite" path || true)"; dir="${dir/#\~/$HOME}"
  [ -n "$dir" ] || dir="$BASE/$suite"
  remote="$(eco_field "$suite" remote || true)"
  [ -n "$remote" ] || remote="https://github.com/$ORG/$suite.git"

  if [ ! -d "$dir/.git" ]; then
    git clone --quiet "$remote" "$dir" || { echo "FAIL clone $remote"; return 1; }
    echo "OK   cloned $suite -> $dir"
    just_cloned=1
  fi
  git -C "$dir" fetch --tags --quiet || { echo "FAIL fetch $suite"; return 1; }

  if [ -n "$(git -C "$dir" status --porcelain)" ]; then
    echo "!!   $suite has local changes in $dir — refusing to move it (developer checkout?)"
    return 1
  fi

  # A consumer checkout lives DETACHED on a release tag (this script put it
  # there). A checkout sitting on a BRANCH is a developer working copy — or a
  # hand-made clone that never converted; moving either under the developer's
  # feet is how work gets lost, so only a clone this run created is converted.
  local branch
  branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD || true)"
  if [ -n "$branch" ] && [ "$just_cloned" = 0 ]; then
    echo "!!   $suite sits on branch '$branch' in $dir — developer checkout, not moving it."
    echo "     Consumer machines convert ONCE by hand: git -C $dir checkout <release-tag>"
    return 1
  fi

  if [ -z "$tag" ]; then
    tag="$(git -C "$dir" tag --list 'v*' --sort=-v:refname | head -1)"
  fi
  if [ -z "$tag" ]; then
    echo "!!   $suite carries no release tag — nothing is released yet, not touching it"
    return 1
  fi
  git -C "$dir" rev-parse --verify --quiet "refs/tags/$tag" >/dev/null \
    || { echo "FAIL $suite has no tag '$tag'"; return 1; }

  if [ "$(git -C "$dir" rev-parse HEAD)" = "$(git -C "$dir" rev-parse "refs/tags/$tag^{commit}")" ]; then
    echo "OK   $suite already at $tag"
  else
    git -C "$dir" checkout --quiet "refs/tags/$tag" || { echo "FAIL checkout $tag"; return 1; }
    echo "OK   $suite -> $tag ($(git -C "$dir" rev-parse --short HEAD))"
  fi

  # contract: the suite says which core it needs; the running core says what it is
  local req have
  req="$(python3 -c "import json;print(json.load(open('$dir/dependencies.json')).get('requires_core',''))" 2>/dev/null || true)"
  have="$(python3 -c "import json;print(json.load(open('$BRAIN/core/core-contract.json'))['contract_version'])" 2>/dev/null || true)"
  [ -n "$req" ] && echo "     requires_core $req — running core contract: ${have:-unknown}"

  # wiring stays a hand step (site-specific launcher/secrets) — point at the notes
  local f
  for f in INSTALL.md README.md; do
    [ -f "$dir/$f" ] && { echo "     wiring: see $dir/$f"; break; }
  done
  return 0
}

failed=0
if [ "$1" = "--all" ]; then
  suites="$(eco_suites)"
  if [ -z "$suites" ]; then
    echo "!!   no suites recorded in $ECO — name one explicitly: suite-install.sh <suite>"
    exit 1
  fi
  for s in $suites; do install_one "$s" || failed=1; done
else
  install_one "$1" "${2:-}" || failed=1
fi

# keep the brain's ecosystem record honest about what now runs here
if [ -f "$ECO" ] && [ -f "$BRAIN/core/scripts/ecosystem-sync.py" ]; then
  python3 "$BRAIN/core/scripts/ecosystem-sync.py" --write >/dev/null 2>&1 \
    && echo "OK   ecosystem record refreshed" \
    || echo "!!   ecosystem record refresh failed — run core/scripts/ecosystem-sync.py --write"
fi

exit $failed
