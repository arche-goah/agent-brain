#!/usr/bin/env bash
# Fixture for scripts/watch-pr.sh: its own --selftest (cutoff substitution, and with jq the
# negative control that an older review stays out). Kept as a test-*.sh so the discovered
# fixture runners (CI, portability-smoke, brain-selftest) execute it on every OS.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$HERE/watch-pr.sh" --selftest
