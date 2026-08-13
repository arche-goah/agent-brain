#!/usr/bin/env bash
# release-preflight.sh — the release-race and broken-tag classes, caught BEFORE they ship.
#
# A release is one atomic promise: tag name, manifest version and CHANGELOG section
# all say the same thing, exactly once, from exactly one session. Every part of that
# promise has failed at least once in the field: a tag was cut with the manifest
# still on the previous version (the plugin cache collides on the version STRING, so
# consumers keep stale content that looks current), and two sessions seeing the same
# merges are one fetch away from assigning the same version twice. Prose guards lose
# against the moment — this script is the mechanical carrier.
#
# Modes:
#   release-preflight.sh vX.Y.Z          # LOCAL, before tagging: full preflight
#   release-preflight.sh --ci-tag vX.Y.Z # CI, on the pushed tag: content checks only
#
# Local checks (all must pass, the summary states its own coverage):
#   1. plugin.json version == tag version
#   2. CHANGELOG.md carries a "## X.Y.Z" section
#   3. the tag does not exist yet, locally or on origin (race guard)
#   4. HEAD is the pushed origin/main state (a release tags shared history,
#      never a local variant)
#   5. no competing open release PR (needs gh; skipped LOUDLY when unavailable)
# CI mode runs 1+2 against the checked-out tag — a broken tag turns red on the
# repo page instead of failing silently on the next consumer update.
#
# Env: RELEASE_PREFLIGHT_ROOT overrides the repo root (tests).
set -uo pipefail

ROOT="${RELEASE_PREFLIGHT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MODE=local
TAG="${1:-}"
if [ "$TAG" = "--ci-tag" ]; then MODE=ci; TAG="${2:-}"; fi
case "$TAG" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "usage: release-preflight.sh [--ci-tag] vX.Y.Z" >&2; exit 2 ;;
esac
VER="${TAG#v}"

checks=0; failed=0
ok()  { checks=$((checks+1)); echo "OK   $1"; }
bad() { checks=$((checks+1)); failed=$((failed+1)); echo "FAIL $1"; }
note(){ echo "     $1"; }

# 1. manifest version == tag — the v1.2.0 class: same version string, different content
MANIFEST="$ROOT/.claude-plugin/plugin.json"
MV="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['version'])" "$MANIFEST" 2>/dev/null || true)"
if [ "$MV" = "$VER" ]; then
  ok "plugin.json version $MV matches $TAG"
else
  bad "plugin.json says '${MV:-unreadable}', tag says '$VER' — a consumer's plugin cache keys on this string and would keep stale content that looks current"
fi

# 2. CHANGELOG section — an untagged change reaches nobody, an unlogged one surprises everybody
if grep -qE "^## ${VER//./\\.}( |$)" "$ROOT/CHANGELOG.md" 2>/dev/null; then
  ok "CHANGELOG.md carries a '## $VER' section"
else
  bad "CHANGELOG.md has no '## $VER' section"
fi

if [ "$MODE" = "local" ]; then
  # 3. race guard: the tag must not exist anywhere yet
  git -C "$ROOT" fetch --tags --quiet 2>/dev/null || note "fetch --tags failed — checking local tags only"
  if git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    bad "tag $TAG already exists — this release happened (other session?); a burned tag is never re-cut, the next number supersedes it"
  else
    ok "tag $TAG does not exist yet (local + fetched)"
  fi

  # 4. a release tags the SHARED state — HEAD must be the pushed origin/main
  git -C "$ROOT" fetch --quiet origin main 2>/dev/null || true
  HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
  MAIN_SHA="$(git -C "$ROOT" rev-parse origin/main 2>/dev/null || true)"
  if [ -n "$HEAD_SHA" ] && [ "$HEAD_SHA" = "$MAIN_SHA" ]; then
    ok "HEAD is origin/main ($(git -C "$ROOT" rev-parse --short HEAD))"
  else
    bad "HEAD (${HEAD_SHA:0:7}) is not origin/main (${MAIN_SHA:0:7}) — tag the pushed shared state, not a local variant"
  fi

  # 5. race guard, second half: someone else's release PR means comment THERE, not tag here
  if command -v gh >/dev/null 2>&1; then
    OPEN="$(gh pr list --state open --json headRefName,title \
      --jq '[.[] | select((.headRefName | startswith("release/")) or (.title | startswith("chore: release")))] | length' 2>/dev/null || echo "?")"
    if [ "$OPEN" = "0" ]; then
      ok "no competing open release PR"
    elif [ "$OPEN" = "?" ]; then
      note "gh query failed — competing-release-PR check NOT run (counts as unchecked, not as green)"
    else
      bad "$OPEN open release PR(s) — the race guard says: comment there instead of cutting a second release"
    fi
  else
    note "gh not available — competing-release-PR check NOT run (counts as unchecked, not as green)"
  fi
fi

echo
if [ "$failed" -eq 0 ]; then
  echo "preflight $TAG: $checks checks run, all green"
else
  echo "preflight $TAG: $failed of $checks checks FAILED — do not tag"
fi
exit "$([ "$failed" -eq 0 ] && echo 0 || echo 1)"
