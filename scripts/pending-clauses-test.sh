#!/usr/bin/env bash
# pending-clauses-test.sh — both-direction fixture for pending-clauses.py.
# A throwaway "core" git repo with one squash-style commit "(#5)" and an instance whose
# rules carry: a clause on a PR that IS in the pin (STALE), one on a PR that is not
# provably in it (READ), one without a number (READ), plain text (silent), and a German
# clause that only instance data can find.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

mkdir -p "$TMP/core" "$TMP/brain/.claude/rules"
git -C "$TMP/core" init -q
git -C "$TMP/core" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "feat: the thing (#5)"

printf '%s\n' \
  '# rules' \
  'The check runs at start once the pin carries it.' \
  'Until core PR #5 lands, use the manual path.' \
  'Until core PR #9 lands, use the other manual path.' \
  'A plain sentence about PR #5 that waits for nothing.' \
  'Gilt erst, sobald der Pin das enthaelt.' > "$TMP/brain/CLAUDE.md"

out=$("$PY" "$HERE/pending-clauses.py" --repo "$TMP/brain" --core "$TMP/core" 2>&1)

grep -q "STALE CLAUDE.md:3 — #5" <<<"$out" && ok "a clause on a PR in the pin is STALE" || bad "a clause on a PR in the pin is STALE"
grep -q "READ  CLAUDE.md:4 — #9 not provably" <<<"$out" && ok "a PR not found is READ, never dropped" || bad "a PR not found is READ, never dropped"
grep -q "READ  CLAUDE.md:2 — pending clause without a PR number" <<<"$out" && ok "a clause without a number is READ" || bad "a clause without a number is READ"
grep -q "CLAUDE.md:5" <<<"$out" && bad "a plain mention of a PR stays silent" || ok "a plain mention of a PR stays silent"
grep -q "CLAUDE.md:6" <<<"$out" && bad "German clause without instance data stays silent" || ok "German clause without instance data stays silent"

printf '{"patterns": ["sobald der Pin"]}\n' > "$TMP/brain/.claude/rules/pending-clauses.json"
out=$("$PY" "$HERE/pending-clauses.py" --repo "$TMP/brain" --core "$TMP/core" 2>&1)
grep -q "READ  CLAUDE.md:6" <<<"$out" && ok "German clause found with instance data" || bad "German clause found with instance data"
grep -q "pending-clauses.json" <<<"$out" && bad "the pattern file does not match itself" || ok "the pattern file does not match itself"

# Negative control: the same instance with every clause resolved prints nothing at all.
printf '%s\n' '# rules' 'The check runs at every start (core v1.4.0).' > "$TMP/brain/CLAUDE.md"
out=$("$PY" "$HERE/pending-clauses.py" --repo "$TMP/brain" --core "$TMP/core" 2>&1)
[ -z "$out" ] && ok "resolved rules: no output" || bad "resolved rules: no output (got: $out)"

echo
if [ "$fails" -eq 0 ]; then echo "pending-clauses-test: all checks passed"; exit 0; fi
echo "pending-clauses-test: $fails check(s) FAILED"; exit 1
