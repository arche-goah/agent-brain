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

# Date conditions (2026-10-31): a forward date clause past its date is EXPIRED; one still ahead,
# history in prose, and a file with its own dated reader stay silent.
printf '%s\n' '# rules' \
  'The probe is an alpha until 2026-10-20, then core PR.' \
  'The probe is an alpha until 2026-12-24, then core PR.' \
  'The value that stood here until 2026-10-01 was replaced.' \
  'Gate runs ALPHA bis 2026-10-20.' > "$TMP/brain/CLAUDE.md"
printf '{"x": {"until": "2026-10-24", "why": "waits on a review"}}\n' > "$TMP/brain/.claude/rules/waits.json"
printf '{"x": {"until": "2026-10-24"}}\n' > "$TMP/brain/.claude/rules/local-machinery.json"
rm -f "$TMP/brain/.claude/rules/pending-clauses.json"
out=$("$PY" "$HERE/pending-clauses.py" --repo "$TMP/brain" --core "$TMP/core" --today 2026-10-31 2>&1)
grep -q "EXPIRED CLAUDE.md:2 — condition date 2026-10-20" <<<"$out" && ok "a forward date clause past its date is EXPIRED" || bad "a forward date clause past its date is EXPIRED (got: $out)"
grep -q 'EXPIRED .claude/rules/waits.json:1 — condition date 2026-10-24' <<<"$out" && ok "a JSON until field past its date is EXPIRED" || bad "a JSON until field past its date is EXPIRED"
grep -q "CLAUDE.md:3" <<<"$out" && bad "a date still ahead stays silent" || ok "a date still ahead stays silent"
grep -q "CLAUDE.md:4" <<<"$out" && bad "history in prose stays silent" || ok "history in prose stays silent"
grep -q "local-machinery.json" <<<"$out" && bad "a file with its own dated reader is left to it" || ok "a file with its own dated reader is left to it"
grep -q "CLAUDE.md:5" <<<"$out" && bad "a German date clause without instance data stays silent" || ok "a German date clause without instance data stays silent"
printf '{"date_words": ["\\\\bALPHA bis\\\\b"]}\n' > "$TMP/brain/.claude/rules/pending-clauses.json"
out=$("$PY" "$HERE/pending-clauses.py" --repo "$TMP/brain" --core "$TMP/core" --today 2026-10-31 2>&1)
grep -q "EXPIRED CLAUDE.md:5" <<<"$out" && ok "a German date clause found with instance date_words" || bad "a German date clause found with instance date_words (got: $out)"

echo
if [ "$fails" -eq 0 ]; then echo "pending-clauses-test: all checks passed"; exit 0; fi
echo "pending-clauses-test: $fails check(s) FAILED"; exit 1
