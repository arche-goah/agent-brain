#!/usr/bin/env bash
# covers: published-text
# Runs scripts/published-text-test.cjs (the fixture of helpers/published-text.cjs) under the
# shell-fixture discovery of CI and portability-smoke, which globs scripts/test-*.sh.
# Usage: bash scripts/test-published-text.sh   (exit 0 = all fixtures pass)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
F="$HERE/published-text-test.cjs"
[ -f "$F" ] || { echo "  --  published-text fixture not in this layout"; exit 0; }
if command -v cygpath >/dev/null 2>&1; then F="$(cygpath -m "$F")"; fi
node "$F"
