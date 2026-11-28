#!/usr/bin/env bash
# reader-fixtures.sh — sourced: `reader_fixtures <repo-dir> <git diff range…>` prints, one per line and relative to the
# repo, the fixtures a change owes: every changed fixture that still exists, and every fixture whose text names the base
# name of a changed path - its readers. ONE rule for both callers, core-push-lint.sh --fast and core-merge-lint.sh
# (review of agent-brain #684, 2026-11-26, Windows: the two scripts carried two copies that differed in four ways - stem
# vs base name, deletes read or not, docs skipped or not, `*-test.cjs` globbed or not).
#   - The paths of a change are read with --name-status: a deleted file and the OLD name of a rename count too - the
#     readers of a file that is gone are the ones that break most surely (the review's probes e and f).
#   - The match is the base name as a fixed string, not the stem: measured 2026-11-28 over the tree, the stem matched 765
#     more (file, fixture) pairs than the base name, led by plain words (`helpers` 125, `checks` 114, `config` 72,
#     `hooks` 41); the base name found the 15 pairs a stem under 4 characters had to skip (`ci.yml`).
#   - Docs (.md/.txt, any case) pull no readers: they name everything; their readers are the lint steps.
# Limits, named: a reader that builds the file name at run time, and a TRANSITIVE reader (a fixture naming gate.cjs, which
# requires the changed lib.cjs - `stop-echo.cjs` is required by 19 helpers and named by no fixture) are not found; a base
# name several files share (hooks.json, settings.json) over-selects.
reader_fixtures() {
  local dir="$1"; shift
  local fx='^scripts/(test-[^/]*\.(sh|py|cjs)|[^/]*-test\.(sh|py|cjs))$' a b f base
  git -C "$dir" -c core.quotepath=off diff --name-status -M "$@" | while IFS=$'\t' read -r _ a b; do
    for f in "$a" "$b"; do
      [ -n "$f" ] || continue
      if printf '%s\n' "$f" | grep -aqE "$fx"; then
        [ -f "$dir/$f" ] && printf '%s\n' "$f"
        continue
      fi
      base="${f##*/}"
      case "$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')" in *.md|*.txt) continue ;; esac
      (cd "$dir" && grep -alF -- "$base" scripts/test-*.sh scripts/test-*.py scripts/test-*.cjs \
        scripts/*-test.sh scripts/*-test.py scripts/*-test.cjs 2>/dev/null)
    done
  done | sort -u
}
