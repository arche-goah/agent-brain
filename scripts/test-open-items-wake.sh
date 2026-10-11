#!/usr/bin/env bash
# Fixture test for the parked-domain wake-up in scripts/open-items.py — both directions, no
# network. A parked domain names the party whose pause parked it (`wake_on`) and the date
# (`since`); a move of that party in that domain after `since` becomes ONE operator item.
# Positive: a PR by that login, a shared-memory fact file from that von, a LOG heading from
# that von. Negative: the same party before `since`, another party after it, and a plain
# string entry (no wake rule) — those stay parked and silent.
# Usage: bash scripts/test-open-items-wake.sh (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
SRC="$(cd "$(dirname "$0")" && pwd)/open-items.py"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
has() { case "$2" in *"$1"*) return 0;; esac; return 1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }

mkdir -p "$T/core/scripts" "$T/root/.claude/rules" "$T/repo"
cp "$SRC" "$T/core/scripts/open-items.py"
cp "$(dirname "$SRC")/instance_key.py" "$T/core/scripts/instance_key.py"
printf '%s\n' 'print("shared-memory open requests to this instance: 0")' > "$T/core/scripts/shared-memory-inbox.py"

# A real git repo standing in for the shared memory, read at origin/main like the real one.
g() { git -C "$T/repo" -c user.name=fixture -c user.email=fixture@example.invalid "$@" >/dev/null 2>&1; }
g init -q
mkdir -p "$T/repo/lightdesk" "$T/repo/core"
fact() { # $1 path, $2 von, $3 date
  printf '%s\n' '---' "name: x" 'metadata:' "  von: $2" "  date: $3" '---' 'body' > "$T/repo/$1"
}
commit_main() { g add -A; g commit -q -m fixture; g update-ref refs/remotes/origin/main HEAD; }

prs() { # $1 author, $2 createdAt, $3 repo
  printf '{"data":{"viewer":{"login":"me"},"search":{"issueCount":1,"nodes":[{"number":9,"title":"fix","isDraft":false,"createdAt":"%s","body":"","author":{"login":"%s"},"repository":{"name":"%s"},"reviewRequests":{"nodes":[]},"latestReviews":{"nodes":[]},"commits":{"nodes":[{"commit":{"committedDate":"%s"}}]},"comments":{"nodes":[]}}]}}}\n' \
    "$2" "$1" "$3" "$2" > "$T/prs.json"
}
cfg() { # $1 parked JSON array
  printf '{"parked": %s, "owners": {"desk-suite": "peer-x"}}\n' "$1" > "$T/root/.claude/rules/open-items.json"
}
run() {
  OPEN_ITEMS_PR_FIXTURE="$(native "$T/prs.json")" "$PY" "$(native "$T/core/scripts/open-items.py")" \
    --owner me --repo "$(native "$T/repo")" --root "$(native "$T/root")" --hook-input '{}' 2>&1
}
WAKE='[{"match": "lightdesk|desk-suite", "name": "lightdesk", "wake_on": ["peer-x", "peer-x-win"], "since": "2026-09-18"}]'

# 1. nothing new since the parking: silent, PR stays parked
fact lightdesk/old-note-2026-09-01.md peer-x-win 2026-09-01; commit_main
prs peer-x 2026-09-09T10:00:00Z desk-suite; cfg "$WAKE"
out=$(run)
has "[wake|" "$out" && bad "activity BEFORE since woke the domain: $out" || ok "activity before since stays silent"
has "[parked] desk-suite#9" "$out" && ok "the old PR stays on the parked line" || bad "old PR not parked: $out"

# 2. another party moves after since: still silent
fact lightdesk/other-2026-10-02.md peer-y 2026-10-02; commit_main
out=$(run)
has "[wake|" "$out" && bad "another party woke the domain: $out" || ok "another party after since stays silent"

# 3. the pausing party opens a PR after since: one operator item
prs peer-x 2026-10-20T08:00:00Z desk-suite
out=$(run)
has "[wake|human] 2026-10-20 lightdesk" "$out" && ok "a new PR of the party wakes the domain (human item)" || bad "PR did not wake: $out"
has "ask the operator whether to unpark" "$out" && ok "the line says what to do" || bad "no instruction: $out"
has "human 1" "$out" && ok "counted as an operator item" || bad "not counted as human: $out"

# 4. a shared-memory fact file of the party after since (PR old again)
prs peer-x 2026-09-09T10:00:00Z desk-suite
fact lightdesk/back-2026-10-12.md peer-x-win 2026-10-12; commit_main
out=$(run)
has "[wake|human] 2026-10-12 lightdesk" "$out" && ok "a fact file of the party wakes the domain" || bad "fact file did not wake: $out"

# 5. a LOG heading of the party after since (fact file removed)
rm "$T/repo/lightdesk/back-2026-10-12.md"
printf '%s\n' '# LOG' '' '## 2026-10-15 · peer-x-win — AN inst-a: back on the desk' 'text' > "$T/repo/lightdesk/LOG.md"
commit_main
out=$(run)
has "[wake|human] 2026-10-15 lightdesk" "$out" && ok "a LOG heading of the party wakes the domain" || bad "LOG heading did not wake: $out"

# 6. a plain string entry (no wake rule) never wakes, and still parks
cfg '["lightdesk|desk-suite"]'
prs peer-x 2026-10-20T08:00:00Z desk-suite
out=$(run)
has "[wake|" "$out" && bad "a plain parked entry woke: $out" || ok "plain string entry: no wake-up"
has "[parked] desk-suite#9" "$out" && ok "plain string entry still parks" || bad "plain entry lost parking: $out"

[ "$fail" = 0 ] && echo "open-items wake-up: all cases pass" || { echo "open-items wake-up: FAILURES"; exit 1; }
