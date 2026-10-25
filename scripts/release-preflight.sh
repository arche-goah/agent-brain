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
#   2b. no fragment left in changelog.d/ and nothing under "## Unreleased"
#   3. the tag does not exist yet, locally or on origin (race guard)
#   4. HEAD is the pushed origin/main state (a release tags shared history,
#      never a local variant)
#   5. no competing open release PR (needs gh; skipped LOUDLY when unavailable)
# Readiness of the STRAND (operator order 2026-10-25, after eight core tags in fifteen days
# and a second beta on one day: "collect cleanly until a pin-worthy state has gathered";
# the carrier "must test more than twice a day — pin maturity of the PRs, expected incoming
# contributions"). A tag is a delivery, never the close of a merge; "the strand is closed"
# was true every evening, so these checks measure it instead of asking:
#   6. main is QUIET: the newest commit on origin/main is older than RELEASE_QUIET_HOURS
#      (default 24) — a strand that still moves is not collected
#   7. no open pull request (drafts excluded) — an open PR is an expected contribution
#   8. nothing announced in the shared memory for this repo's topic: no entry with
#      `status: open` under <shared repo>/<topic>/ (RELEASE_TOPIC, default from the repo
#      name: agent-brain -> core, <x>-suite -> <x>; SHARED_MEMORY_REPO, default
#      ~/Projects/brain-shared-memory; no clone = said, not green)
#   9. every PR merged since the previous tag carries BOTH OS proofs in its thread: a body
#      or comment with an instance key that says macOS, and one that says Windows
#  10. the consumer is named: RELEASE_CONSUMER="<who gets this tag and why now>"
# Earlier than the strand allows ONLY on the operator's word: RELEASE_EARLY_OK="<quote> <YYYY-MM-DD>"
# (a quotation in quote marks plus the date it was said) lets 6, 7 and 8 pass and prints the
# quote; 9 and 10 are never waived. Measured on the real case: v2.0.4 was cut 29 minutes
# after the last merge with eight PRs opened half an hour later — 6 and 7 would have refused it.
# CI mode runs 1, 2 and 2b against the checked-out tag — a broken tag turns red on the
# repo page instead of failing silently on the next consumer update.
#
# Env: RELEASE_PREFLIGHT_ROOT overrides the repo root (tests); RELEASE_QUIET_HOURS,
# RELEASE_TOPIC, SHARED_MEMORY_REPO, RELEASE_CONSUMER, RELEASE_EARLY_OK as above.
set -uo pipefail

# Resolve the Python interpreter: the python.org installer on Windows ships ONLY
# `python`, and the Microsoft Store ships a `python3` STUB that resolves in PATH but
# does not run — so probe by RUNNING it, never with `command -v` (measured 2026-08-14:
# a colleague brain had no working `python3`, every reader below returned empty and
# brain-update.sh printed DONE without having done anything).
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python

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
MV="$("$PY" -c "import json,sys;print(json.load(open(sys.argv[1]))['version'])" "$MANIFEST" 2>/dev/null || true)"
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

# 2b. nothing left behind: a fragment in changelog.d/ or an entry still under ## Unreleased
# would ship in the tag without being in its section (changelog.d/README.md)
left="$(find "$ROOT/changelog.d" -maxdepth 1 -name '*.md' ! -iname 'readme.md' 2>/dev/null | wc -l | tr -d ' ')"
unrel="$(awk '/^## Unreleased/{u=1;next} /^## /{u=0} u && NF' "$ROOT/CHANGELOG.md" 2>/dev/null | wc -l | tr -d ' ')"
if [ "$left" = "0" ] && [ "$unrel" = "0" ]; then
  ok "no CHANGELOG fragment left behind (changelog.d/ empty, ## Unreleased empty)"
else
  bad "$left fragment(s) in changelog.d/ and $unrel line(s) under ## Unreleased not in a version section — run: python3 scripts/changelog-assemble.py $VER"
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
  # gh resolves the repo from its working directory, not from $ROOT — run it IN $ROOT,
  # or a preflight started from another checkout (brain -> suite) asks the wrong repo
  # and reports that repo's green as this one's (measured 2026-09-23: agent-brain
  # answered for touchdesigner-suite).
  if command -v gh >/dev/null 2>&1; then
    OPEN="$(cd "$ROOT" && gh pr list --state open --json headRefName,title \
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

  # --- readiness of the strand (6-10) ---------------------------------------------------
  EARLY="${RELEASE_EARLY_OK:-}"
  early_ok=0
  if [ -n "$EARLY" ]; then
    # the operator's word in checkable form: quote marks around words, plus the date it was said
    if printf '%s' "$EARLY" | grep -qE '["“„].+["”“]' && printf '%s' "$EARLY" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
      early_ok=1; note "RELEASE_EARLY_OK carries the operator's word: $EARLY — checks 6-8 pass on it, 9 and 10 still run"
    else
      note "RELEASE_EARLY_OK set but it is no quotation with a date (\"…\" YYYY-MM-DD) — ignored, a paraphrase is not the operator's word"
    fi
  fi

  # 6. quiet main
  QH="${RELEASE_QUIET_HOURS:-24}"
  LAST_TS="$(git -C "$ROOT" log -1 --format=%ct origin/main 2>/dev/null || echo 0)"
  NOW_TS="$(date +%s)"
  AGE_H=$(( (NOW_TS - LAST_TS) / 3600 ))
  if [ "$early_ok" = 1 ]; then
    ok "main quiet for ${AGE_H} h — waived by the operator's word"
  elif [ "$LAST_TS" != 0 ] && [ "$AGE_H" -ge "$QH" ]; then
    ok "main quiet for ${AGE_H} h (floor ${QH} h) — the strand has settled"
  else
    bad "main moved ${AGE_H} h ago (floor ${QH} h) — the strand is still collecting; a tag is a delivery, not the close of a merge"
  fi

  # 7. open pull requests = expected contributions
  if command -v gh >/dev/null 2>&1; then
    OPEN_PRS="$(cd "$ROOT" && gh pr list --state open --json number,isDraft --jq '[.[] | select(.isDraft | not) | .number] | join(" ")' 2>/dev/null || echo "?")"
    if [ "$OPEN_PRS" = "?" ]; then
      note "gh query failed — open-PR check NOT run (counts as unchecked, not as green)"
    elif [ -z "$OPEN_PRS" ]; then
      ok "no open pull request"
    elif [ "$early_ok" = 1 ]; then
      ok "open PR(s) #${OPEN_PRS// / #} — waived by the operator's word"
    else
      bad "open PR(s) #${OPEN_PRS// / #} — expected contributions; merge or close them, then collect"
    fi
  else
    note "gh not available — open-PR check NOT run (counts as unchecked, not as green)"
  fi

  # 8. nothing announced in the shared memory for this repo's topic
  SHARED="${SHARED_MEMORY_REPO:-$HOME/Projects/brain-shared-memory}"
  base="$(basename "$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$ROOT")")"
  case "$base" in agent-brain) dtopic=core ;; *-suite) dtopic="${base%-suite}" ;; *) dtopic="$base" ;; esac
  TOPIC="${RELEASE_TOPIC:-$dtopic}"
  if [ -d "$SHARED/$TOPIC" ]; then
    # the generated OPEN.md already settles entries answered elsewhere (answers:/closes:); without
    # it, the raw status fields of the files decide
    if [ -f "$SHARED/$TOPIC/OPEN.md" ]; then
      ANN_N="$(grep -aoE '^[0-9]+ open entr' "$SHARED/$TOPIC/OPEN.md" | grep -aoE '^[0-9]+' | head -1)"
      ANN="$(grep -aoE '\[[^]]+\]' "$SHARED/$TOPIC/OPEN.md" | head -5 | tr '\n' ' ')"
    else
      ANN="$(grep -alE '^  status: open$' "$SHARED/$TOPIC"/*.md 2>/dev/null | sed 's|.*/||' | head -5 | tr '\n' ' ')"
      ANN_N="$(grep -lE '^  status: open$' "$SHARED/$TOPIC"/*.md 2>/dev/null | wc -l | tr -d ' ')"
    fi
    ANN_N="${ANN_N:-0}"
    if [ "$ANN_N" = 0 ]; then
      ok "nothing open in the shared memory under $TOPIC/"
    elif [ "$early_ok" = 1 ]; then
      ok "$ANN_N open entr(y|ies) under $TOPIC/ — waived by the operator's word"
    else
      bad "$ANN_N open entr(y|ies) in the shared memory under $TOPIC/ (announced or awaited contributions): ${ANN}— answer or close them, then collect"
    fi
  else
    note "no shared-memory clone at $SHARED/$TOPIC — announced-contributions check NOT run (counts as unchecked, not as green)"
  fi

  # 9. both OS proofs on every PR merged since the previous tag — pin maturity
  PREV="$(git -C "$ROOT" describe --tags --abbrev=0 origin/main 2>/dev/null || true)"
  if [ -n "$PREV" ]; then RANGE="$PREV..origin/main"; else RANGE="origin/main"; fi
  PRS="$(git -C "$ROOT" log --format=%s "$RANGE" 2>/dev/null | grep -oE 'Merge pull request #[0-9]+|\(#[0-9]+\)$' | grep -oE '[0-9]+' | sort -un | tr '\n' ' ')"
  if [ -z "$PRS" ]; then
    ok "no PR merged since ${PREV:-the first commit} — nothing to prove"
  elif command -v gh >/dev/null 2>&1; then
    missing=""
    for n in $PRS; do
      # one base64 line per text (body, each comment): the key test and the OS words are read
      # HERE, per text, so a comment that says "Windows" without a key never counts
      B64="$(cd "$ROOT" && gh pr view "$n" --json body,comments --jq '([.body] + [.comments[].body]) | .[] | @base64' 2>/dev/null || echo "?")"
      if [ "$B64" = "?" ]; then missing="$missing #$n(unreadable)"; continue; fi
      has_mac=0; has_win=0
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        txt="$(printf '%s' "$line" | base64 -d 2>/dev/null || true)"
        printf '%s' "$txt" | grep -q 'instance-key:' || continue
        printf '%s' "$txt" | grep -qi 'macos' && has_mac=1
        printf '%s' "$txt" | grep -qi 'windows' && has_win=1
      done <<< "$B64"
      [ "$has_mac" = 1 ] && [ "$has_win" = 1 ] || missing="$missing #$n($( [ "$has_mac" = 1 ] && echo "no Windows" || { [ "$has_win" = 1 ] && echo "no macOS" || echo "neither"; } ))"
    done
    if [ -z "$missing" ]; then
      ok "every PR since ${PREV:-the start} carries a macOS and a Windows proof (${PRS% })"
    else
      bad "PR(s) without both OS proofs in the thread:$missing — a tag ships only what was checked on both"
    fi
  else
    note "gh not available — OS-proof check NOT run (counts as unchecked, not as green)"
  fi

  # 10. the consumer is named
  if [ -n "${RELEASE_CONSUMER:-}" ]; then
    ok "consumer named: ${RELEASE_CONSUMER}"
  else
    bad "no consumer named — set RELEASE_CONSUMER=\"<who gets this tag and why now>\"; a tag nobody pulls is noise"
  fi
fi

echo
if [ "$failed" -eq 0 ]; then
  echo "preflight $TAG: $checks checks run, all green"
else
  echo "preflight $TAG: $failed of $checks checks FAILED — do not tag"
fi
exit "$([ "$failed" -eq 0 ] && echo 0 || echo 1)"
