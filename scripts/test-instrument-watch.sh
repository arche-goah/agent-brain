#!/usr/bin/env bash
# covers: instrument-watch
#
# Fixture for scripts/instrument-watch.py: an instrument for an unexplained failure is owed while its
# cause stays open (operator order 2026-10-29). Both directions, process list through the fixture seam.
# Usage: bash scripts/test-instrument-watch.sh   (exit 0 = all pass)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

mkdir -p "$T/b/.claude/rules" "$T/b/docs"
printf '{"ledgers":["docs/ledger.md"]}' > "$T/b/.claude/rules/ledgers.json"
printf '{"instruments":[{"id":"app-exit-watch","match":"app-watch.sh","cause":"app-exit","start":"bash scripts/app-watch.sh (detached)"}]}' \
  > "$T/b/.claude/rules/instruments.json"
ledger() { printf -- '- [%s] **the app quits without a trace**\n  id: app-exit\n  class: todo\n' "$1" > "$T/b/docs/ledger.md"; }
run() { "$PY" "$HERE/instrument-watch.py" --repo "$(native "$T/b")" --ps-output "$(native "$T/ps.txt")"; }

ledger " "; printf 'bash scripts/other.sh\n' > "$T/ps.txt"
out=$(run); grep -q "^!! instrument 'app-exit-watch' is not running, its cause 'app-exit' is still open" <<< "$out" \
  && ok "open cause, instrument not running: reported with its start command" || bad "not running: '$out'"
printf 'bash scripts/app-watch.sh\n' > "$T/ps.txt"
out=$(run); [[ -z "$out" ]] && ok "open cause, instrument running: silent" || bad "running: '$out'"
ledger "x"; printf 'bash scripts/other.sh\n' > "$T/ps.txt"
out=$(run); [[ -z "$out" ]] && ok "cause explained (ticked): the instrument is no longer owed" || bad "ticked: '$out'"
printf -- '- [ ] **something else**\n  id: other\n' > "$T/b/docs/ledger.md"
out=$(run); grep -q "its cause 'app-exit' stands in no registered ledger" <<< "$out" && ok "cause in no ledger: stale instrument named" || bad "stale: '$out'"
rm -f "$T/b/.claude/rules/instruments.json"
out=$(run); [[ -z "$out" ]] && ok "no instruments declared: silent" || bad "none: '$out'"

(( fail )) && { echo "test-instrument-watch: FAILED"; exit 1; }
echo "test-instrument-watch: all checks passed"
