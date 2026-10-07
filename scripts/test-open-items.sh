#!/usr/bin/env bash
# Fixture test for scripts/open-items.py — both directions, no network.
# A fake shared-memory-inbox.py next to a copy of the script stands in for the real inbox;
# --owner "" skips the PR search. Proves: the repeat counter (same session once, a new
# session louder), a LOG-only request is listed, a capped / unreadable / "not checked"
# inbox reads as NOT checked (never as "nothing open"), "nothing open" is said when both
# sources are clean, parked items stay on one line, a lost counter says so.
# Usage: bash scripts/test-open-items.sh (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
SRC="$(cd "$(dirname "$0")" && pwd)/open-items.py"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
[ -f "$SRC" ] || { echo "  FAIL script missing: $SRC"; exit 1; }

mkdir -p "$T/core/scripts" "$T/repo/.git" "$T/root"
cp "$SRC" "$T/core/scripts/open-items.py"
# The fake inbox prints whatever $T/inbox.txt holds.
printf '%s\n' 'import os, sys' \
  'sys.stdout.write(open(os.path.join(os.path.dirname(__file__), "..", "..", "inbox.txt"), encoding="utf-8").read())' \
  > "$T/core/scripts/shared-memory-inbox.py"

# OS-3: python is a native process; a Git-Bash /tmp path handed to it as DATA (--repo,
# --root) does not resolve on Windows, and every case would read an empty tree.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
run() { # $1 session id, [$2 root]
  "$PY" "$(native "$T/core/scripts/open-items.py")" --owner "" --repo "$(native "$T/repo")" \
    --root "$(native "${2:-$T/root}")" --hook-input "{\"session_id\":\"$1\"}" 2>&1
}
has() { case "$2" in *"$1"*) return 0;; esac; return 1; }

printf '%s\n' 'shared-memory open requests to this instance: 2' \
  '  - 2026-09-05 [show-tools] peer-b: ANFRAGE an inst-a (show-tools/anfrage-td-2026-09-05.md)' \
  '  - 2026-10-05 [core] peer-b: AN inst-a: #196 Windows-Check OK (LOG)' > "$T/inbox.txt"

out=$(run a)
has "open for us: 2" "$out" && ok "count line" || bad "count line: $out"
has "2026-10-05 core/LOG" "$out" && ok "LOG-only request listed" || bad "LOG request missing: $out"
has "first report" "$out" && ok "first session = first report" || bad "first report: $out"
out=$(run a)
has "!! reported in" "$out" && bad "same session counted twice: $out" || ok "same session counts once"
out=$(run b)
has "!! reported in 2 sessions" "$out" && ok "new session is louder" || bad "no escalation: $out"

# Capped list: the inbox says 3, prints 2 — must read as NOT checked.
sed -i.bak 's/instance: 2/instance: 3/' "$T/inbox.txt"
out=$(run c)
has "shared-memory requests NOT checked" "$out" && ok "count mismatch = NOT checked" || bad "count mismatch silent: $out"
has "- nothing open" "$out" && bad "count mismatch read as nothing open" || ok "count mismatch is not 'nothing open'"

# SHARED_MEMORY_SELF unset: the inbox says "not checked".
printf '%s\n' 'shared-memory open requests: not checked - SHARED_MEMORY_SELF unset' > "$T/inbox.txt"
out=$(run d)
has "NOT checked" "$out" && ok "inbox 'not checked' = NOT checked" || bad "unset SELF read as clean: $out"

# Clean: zero requests, no owner.
printf '%s\n' 'shared-memory open requests to this instance: 0 (last 36500 days)' > "$T/inbox.txt"
out=$(run e)
has "- nothing open" "$out" && ok "clean = 'nothing open' said" || bad "clean not said: $out"
has "open for us: 0" "$out" && ok "clean count 0" || bad "clean count: $out"

# Parked: one line, not dropped, not counted as active.
mkdir -p "$T/root/.claude/rules"
printf '%s\n' '{"parked":["grandma"]}' > "$T/root/.claude/rules/open-items.json"
printf '%s\n' 'shared-memory open requests to this instance: 1' \
  '  - 2026-09-08 [grandma3] peer-c: Rueckfrage (grandma3/rueckfrage-2026-09-08.md)' > "$T/inbox.txt"
out=$(run f)
has "open for us: 0 — ai 0 · human 0 · unclassified 0 (+1 parked)" "$out" && ok "parked counted apart" || bad "parked count: $out"
has "[parked] rueckfrage-2026-09-08.md" "$out" && ok "parked line kept" || bad "parked line missing: $out"

# WHO acts: circle field in the request file (read at origin/main), a request addressed to
# a person by name, an agent class from --classify, and the rest printed as '?'.
GIT() { git -C "$T/repo" -c user.name=t -c user.email=t@t "$@" >/dev/null 2>&1; }
rm -rf "$T/repo" && mkdir -p "$T/repo/core" "$T/repo/ops" && GIT init -q
printf '%s\n' '---' 'name: a' 'metadata:' '  von: peer-b' '  circle: C' '---' 'body' > "$T/repo/core/anfrage-c-2026-09-13.md"
printf '%s\n' '---' 'name: b' 'metadata:' '  von: peer-b' '  circle: E' '---' 'body' > "$T/repo/ops/anfrage-e-2026-09-26.md"
printf '%s\n' '---' 'name: c' 'metadata:' '  von: peer-c' '---' 'body' > "$T/repo/ops/anfrage-x-2026-09-06.md"
GIT add -A && GIT commit -q -m init && GIT update-ref refs/remotes/origin/main HEAD
printf '%s\n' '{"humans":["Opname"]}' > "$T/root/.claude/rules/open-items.json"
printf '%s\n' 'shared-memory open requests to this instance: 5' \
  '  - 2026-09-13 [core] peer-b: ANFRAGE an inst-a (core/anfrage-c-2026-09-13.md)' \
  '  - 2026-09-26 [ops] peer-b: ANFRAGE an inst-a (ops/anfrage-e-2026-09-26.md)' \
  '  - 2026-09-06 [ops] peer-c: ANFRAGE an Opname-mac, braucht Netz (ops/anfrage-x-2026-09-06.md)' \
  '  - 2026-09-08 [ops] peer-c: Rueckfrage an Opname (ops/rueckfrage-y-2026-09-08.md)' \
  '  - 2026-10-05 [core] peer-b: AN inst-a: Check OK (LOG)' > "$T/inbox.txt"
out=$(run h)
has "[request|ai] 2026-09-13" "$out" && ok "circle C = ai" || bad "circle C: $out"
has "[request|human] 2026-09-26" "$out" && ok "circle E = human" || bad "circle E: $out"
has "[request|human] 2026-09-08" "$out" && ok "addressed to a person = human" || bad "person: $out"
has "[request|?] 2026-09-06" "$out" && ok "no data = '?'" || bad "unclassified: $out"
has "[request|?] 2026-09-06" "$out" && ok "machine id built from the name is not the person" || bad "machine id read as a person: $out"
has "unclassified 2" "$out" && ok "header counts the '?'" || bad "header: $(head -1 <<<"$out")"
has "classify every '?' item" "$out" && ok "'?' asks for --classify" || bad "no classify hint: $out"
"$PY" "$(native "$T/core/scripts/open-items.py")" --root "$(native "$T/root")" \
  --classify 'anfrage-x-2026-09-06.md=human:needs the operator net definition' >/dev/null 2>&1
out=$(run i)
has "[request|human] 2026-09-06" "$out" && ok "--classify by file name sticks" || bad "classify lost: $out"
has "needs the operator net definition" "$out" && ok "the reason is printed" || bad "reason missing: $out"
out=$("$PY" "$(native "$T/core/scripts/open-items.py")" --root "$(native "$T/root")" --classify 'x=maybe' 2>&1)
has "bad --classify" "$out" && ok "bad class refused" || bad "bad class accepted: $out"

# A counter that cannot be saved says so (root is a FILE, so .claude-state cannot exist).
printf x > "$T/rootfile"
out=$(run g "$T/rootfile")
has "repeat counter NOT saved" "$out" && ok "lost counter is loud" || bad "lost counter silent: $out"

[ "$fail" = 0 ] && echo "open-items: all cases pass" || { echo "open-items: FAILURES"; exit 1; }
