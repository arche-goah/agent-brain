#!/usr/bin/env bash
# core-push-lint.sh [--fast] <worktree> — the core's CI lint (ci-lint-local.sh) on a core branch worktree, BEFORE its
# push. Green stamps that worktree's HEAD (<brain>/.claude-state/core-push-lint/<sha>.ok, or <sha>.fast.ok); the push
# gate in helpers/core-merge-lint-gate.cjs reads it. A new commit makes the stamp stale.
# long-run: detached
#
# WHY (ported 2026-11-17 from an instance alpha, in use since 2026-10-30): pushed on fixtures alone, the CI lint went
# red minutes later — 2026-10-21 twice, three runs on 2026-10-26, 2026-10-30 (a changelog fragment without its higher
# level). ci-lint-local.sh existed; nothing ran it before a push.
#
# --fast (2026-10-31): the lint jobs without the fixture suites, plus only the fixtures the branch touches, in seconds;
# stamps `<sha>.fast.ok`, which the push gate accepts. The full suites run once, at a merge train's head (merge-train.sh)
# and in the CI on every OS — a full local run per branch queued ten branches for ~2 h on 2026-11-11
# (mechanism-rules.json row: a full run outside a train head is held).
# Run it detached (Working Rule #13); exit 0 = green and stamped, 1 = red, 2 = could not run.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/project-dir.sh"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python   # Windows: python3 can be the Store stub (OS-17)
FAST=0; [ "${1:-}" = "--fast" ] && { FAST=1; shift; }
DIR="${1:-}"
[ -n "$DIR" ] && [ -f "$DIR/scripts/ci-lint-local.sh" ] || { echo "usage: core-push-lint.sh [--fast] <core-worktree>" >&2; exit 2; }
ROOT="$(resolve_project_dir "$HERE")"
STAMPS="${CORE_PUSH_LINT_STAMPS:-$ROOT/.claude-state/core-push-lint}"
mkdir -p "$STAMPS"
head="$(git -C "$DIR" rev-parse HEAD)" || exit 2
[ -z "$(git -C "$DIR" status --porcelain --untracked-files=no)" ] || { echo "core-push-lint: uncommitted changes in $DIR — commit first, the stamp names a commit"; exit 2; }
# One run per machine at a time (2026-11-02, measured: load 57, eleven parallel runs from three sessions, 5-15 min each
# instead of ~15 s — every run slowed every other). A commit already stamped is not linted again.
want="$STAMPS/$head.ok"; [ "$FAST" -eq 1 ] && want="$STAMPS/$head.fast.ok"
if [ -f "$STAMPS/$head.ok" ] || [ -f "$want" ]; then
  echo "core-push-lint: GREEN ${head:0:7} — already stamped ($(cat "$STAMPS/$head.ok" 2>/dev/null || cat "$want"))"
  exit 0
fi
# The commits themselves, with the brain's watch list (2026-11-04, measured: two PRs from a fresh clone went red in the
# CI step "leak scan (commits)" — the clone committed under the global git identity; the local scan had no list and
# said 0 findings, the CI reads its secret list). Red = no stamp, before the long lint even starts.
NAMES="${CORE_PUSH_LINT_NAMES:-$ROOT/.claude/rules/leak-names.json}"
# The tree scan inside ci-lint-local.sh (step leaks) reads the same list from the environment.
if [ -f "$NAMES" ]; then LEAK_NAMES_JSON="$(cat "$NAMES")"; export LEAK_NAMES_JSON; fi
if [ -f "$NAMES" ] && git -C "$DIR" rev-parse --verify -q origin/main >/dev/null; then
  cscan="$(cd "$DIR" && "$PY" scripts/leak-scan.py --no-tree --commits origin/main..HEAD 2>&1)"; crc=$?
  if [ "$crc" -ne 0 ]; then
    printf '%s\n' "$cscan"
    echo "core-push-lint: RED ${head:0:7} — a commit to be pushed carries a watch-listed name or address (author, committer or message); set the clone's identity (git config user.name/user.email, the core convention) and re-create the commit"
    exit 1
  fi
fi
LOCK="${CORE_PUSH_LINT_LOCK:-$STAMPS/.lock}"
waited=0
until mkdir "$LOCK" 2>/dev/null; do
  # A lock whose owner died is taken over (its pid file names a process that is gone).
  owner="$(cat "$LOCK/pid" 2>/dev/null)"
  if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then rm -rf "$LOCK"; continue; fi
  [ "$waited" -eq 0 ] && echo "core-push-lint: queued behind pid ${owner:-?} (one run per machine)"
  waited=$((waited + 1)); sleep 5
  # Waiting for another run of the same commit: its stamp ends the wait.
  if [ -f "$want" ]; then echo "core-push-lint: GREEN ${head:0:7} — stamped by the run ahead"; exit 0; fi
done
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT
# The tree is busy while the lint reads it: the guard holds a branch switch or reset there meanwhile (2026-11-23).
. "$HERE/busy-tree.sh"; busy_tree_mark "$DIR" "core-push-lint ${head:0:7}"
# The stamp names the commit read at the start, the lint reads the files at run time (2026-11-03, measured: a run queued
# 20 min while two commits landed in its worktree — it would have stamped the old sha for the new files).
moved() { [ "$(git -C "$DIR" rev-parse HEAD)" != "$head" ] || [ -n "$(git -C "$DIR" status --porcelain --untracked-files=no)" ]; }
if moved; then echo "core-push-lint: HEAD of $DIR moved while queued (was ${head:0:7}) — run again for the new commit"; exit 2; fi
if [ "$FAST" -eq 1 ]; then
  out="$(cd "$DIR" && bash scripts/ci-lint-local.sh leaks lint shellcheck 2>&1)"; rc=$?
  summary="$(printf '%s\n' "$out" | grep -a 'ci-lint-local:' | tail -1)"
  base="$(git -C "$DIR" merge-base HEAD origin/main 2>/dev/null)"
  n=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n + 1))
    case "$f" in *.py) (cd "$DIR" && "$PY" "$f" >/dev/null 2>&1) ;; *.cjs) (cd "$DIR" && node "$f" >/dev/null 2>&1) ;; *) (cd "$DIR" && bash "$f" >/dev/null 2>&1) ;; esac
    [ $? -eq 0 ] || { rc=1; out="$out
  FAIL touched fixture $f"; }
  done < <(git -C "$DIR" diff --name-only --diff-filter=d "${base:-HEAD~1}" HEAD | grep -aE '^scripts/(test-[^/]*\.(sh|py|cjs)|[^/]*-test\.(sh|py|cjs))$')
  summary="$summary; $n touched fixture(s)"
  stamp="$STAMPS/$head.fast.ok"
else
  # The fixture suites (job portability) run too: 2026-10-30 a branch stamped green on leaks/lint/shellcheck went red
  # in CI in a fixture (its copy list missed a new import).
  out="$(cd "$DIR" && bash scripts/ci-lint-local.sh leaks lint shellcheck portability 2>&1)"; rc=$?
  summary="$(printf '%s\n' "$out" | grep -a 'ci-lint-local:' | tail -1)"
  stamp="$STAMPS/$head.ok"
fi
if moved; then echo "core-push-lint: HEAD of $DIR moved during the run (was ${head:0:7}) — no stamp, run again"; exit 2; fi
if [ "$rc" -eq 0 ]; then
  printf '%s\n' "$summary" > "$stamp"
  echo "core-push-lint: GREEN ${head:0:7} — $summary"
  exit 0
fi
printf '%s\n' "$out" | grep -aE '^ *FAIL|ci-lint-local:'
echo "core-push-lint: RED ${head:0:7}"
exit 1
