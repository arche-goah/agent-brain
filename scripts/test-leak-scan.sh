#!/usr/bin/env bash
# Fixture for scripts/leak-scan.py: the three surfaces (tree, --commits, --text), the
# watch list from LEAK_NAMES_JSON, redaction in CI, and LEAK_NAMES_REQUIRED.
# Why: before the second history cut (2026-10-18) the repo held 84 commits with a private
# author address and 22 messages naming people while the scan stayed green — it read files
# only, knew no email class, and ran without a names list in CI.
# Sandbox only (bash, git, mktemp, python). Exit 0 = all pass.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCAN="$HERE/leak-scan.py"
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

R="$TMP/repo"
git -c init.defaultBranch=main init -q "$R"
git -C "$R" config core.autocrlf false
# Addresses are built at run time so this file itself carries none.
PRIV="kim.sample@$(printf 'mail').$(printf 'net')"
NOREPLY="1+kim@users.noreply.github.com"
git -C "$R" config user.email "$NOREPLY"
git -C "$R" config user.name kim
printf 'contact: user@example.com\nsee git@github.com\n' > "$R/clean.md"
git -C "$R" add -A
git -C "$R" commit -qm "clean start"
BASE=$(git -C "$R" rev-parse HEAD)
git -C "$R" -c user.email="$PRIV" commit -q --allow-empty -m "fix: small thing"
git -C "$R" commit -q --allow-empty -m "docs: as Zorbanek said"

run() { env -u LEAK_NAMES_JSON -u LEAK_NAMES_REQUIRED -u GITHUB_ACTIONS "$@"; }

OUT=$(run "$PY" "$SCAN" --root "$R" 2>&1); rc=$?
[[ $rc -eq 0 ]] && pass "tree with reserved and noreply addresses is clean" || fail "clean tree flagged: $OUT"

printf 'mail me: %s\n' "$PRIV" > "$R/leak.md"
OUT=$(run "$PY" "$SCAN" --root "$R" 2>&1); rc=$?
[[ $rc -eq 1 ]] && grep -q '\[email\] leak.md:1' <<<"$OUT" && pass "a private address in a file is found" \
  || fail "private address in file missed: $OUT"
rm "$R/leak.md"

OUT=$(run "$PY" "$SCAN" --root "$R" --no-tree --commits "$BASE..HEAD" 2>&1); rc=$?
grep -q 'author:1' <<<"$OUT" && grep -q 'committer:1' <<<"$OUT" && pass "a private commit identity is found (author and committer)" \
  || fail "commit identity missed: $OUT"
# NEGATIVE CONTROL: the clean range before it has no finding.
OUT=$(run "$PY" "$SCAN" --root "$R" --no-tree --commits "$BASE~0..$BASE" 2>&1); rc=$?
[[ $rc -eq 0 ]] && pass "control: an empty range is clean" || fail "control range flagged: $OUT"

OUT=$(run LEAK_NAMES_JSON='{"names":["zorbanek"]}' "$PY" "$SCAN" --root "$R" --no-tree --commits "$BASE..HEAD" 2>&1)
grep -q '\[person\] commit:.*:message' <<<"$OUT" && pass "a name from LEAK_NAMES_JSON is found in a commit message" \
  || fail "name in message missed: $OUT"
grep -qi 'zorbanek' <<<"$OUT" && fail "a name from the secret list is echoed into the log" || pass "names from the secret list are redacted"

OUT=$(run GITHUB_ACTIONS=true "$PY" "$SCAN" --root "$R" --no-tree --commits "$BASE..HEAD" 2>&1)
grep -q "${PRIV%%@*}" <<<"$OUT" && fail "CI log repeats the private address" || pass "CI redacts the address it found"

printf 'Title: tidy\n\nThanks Zorbanek for the review.\n' > "$TMP/pr.txt"
OUT=$(run LEAK_NAMES_JSON='{"names":["zorbanek"]}' "$PY" "$SCAN" --root "$R" --no-tree --text "$TMP/pr.txt" 2>&1); rc=$?
[[ $rc -eq 1 ]] && grep -q 'text:pr.txt' <<<"$OUT" && pass "a name in PR text is found" || fail "PR text missed: $OUT"

# A login that contains the name is the public account, not the name (noreply address, author
# field); the bare name in the same text still counts.
printf 'Author: Zorbanek-lights <2+Zorbanek-lights@users.noreply.github.com>\n' > "$TMP/acct.txt"
OUT=$(run LEAK_NAMES_JSON='{"names":["zorbanek"],"accounts":["Zorbanek-lights"]}' "$PY" "$SCAN" --root "$R" --no-tree --text "$TMP/acct.txt" 2>&1); rc=$?
[[ $rc -eq 0 ]] && pass "a name inside a listed login is not a finding" || fail "login flagged as a name: $OUT"
printf 'Thanks Zorbanek, as Zorbanek-lights wrote\n' > "$TMP/acct2.txt"
OUT=$(run LEAK_NAMES_JSON='{"names":["zorbanek"],"accounts":["Zorbanek-lights"]}' "$PY" "$SCAN" --root "$R" --no-tree --text "$TMP/acct2.txt" 2>&1); rc=$?
[[ $rc -eq 1 ]] && pass "control: the bare name next to the login is still found" || fail "bare name masked with the login: $OUT"

OUT=$(run LEAK_NAMES_REQUIRED=1 "$PY" "$SCAN" --root "$R" --no-tree 2>&1); rc=$?
[[ $rc -eq 2 ]] && pass "a required watch list that is missing fails (exit 2)" || fail "missing list passed silently (rc=$rc): $OUT"
OUT=$(run LEAK_NAMES_REQUIRED=1 LEAK_NAMES_JSON='{"names":["zorbanek"]}' "$PY" "$SCAN" --root "$R" --no-tree 2>&1); rc=$?
[[ $rc -eq 0 ]] && pass "a required watch list that is present runs" || fail "present list refused (rc=$rc): $OUT"

exit $FAIL
