#!/usr/bin/env bash
# Fixture for scripts/watch-readiness.py — both directions, offline, in a temp brain.
# Usage: bash scripts/test-watch-readiness.sh   (exit 0 = all pass)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1: $2"; fail=1; }

B="$T/brain"; SM="$T/sm"; mkdir -p "$B/.claude/rules" "$B/.claude-state"
run() { env -u SHARED_MEMORY_SELF SHARED_MEMORY_REPO="$(native "$SM")" "$@" "$PY" "$HERE/watch-readiness.py" --root "$(native "$B")" 2>&1; }
has()  { case "$3" in *"$2"*) ok "$1";; *) bad "$1" "'$3'";; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "'$3'";; *) ok "$1";; esac; }
TODAY="$("$PY" -c 'import datetime;print(datetime.date.today())')"

# 1 — not part of shared memory: silent
out="$(run)"; [ -z "$out" ] && ok "outside shared memory: silent" || bad "outside shared memory: silent" "'$out'"

# 2 — the fresh brain (measured 2026-10-16 on the Mac mini): clone, no config, no self id
mkdir -p "$SM/.git"
out="$(run)"
has "fresh brain: names the missing collab-watch.json" "no .claude/rules/collab-watch.json" "$out"
has "fresh brain: names the missing SHARED_MEMORY_SELF" "SHARED_MEMORY_SELF is not set" "$out"

# 3 — the template copied but not filled
cp "$HERE/../templates/rules-instance/collab-watch.json" "$B/.claude/rules/collab-watch.json"
out="$(run SHARED_MEMORY_SELF=me-mac)"
has "template copy: placeholders named" "still carries template placeholders" "$out"
hasnt "self id from the env counts" "SHARED_MEMORY_SELF is not set" "$out"

# 4 — filled config, self id only in the brain's settings env (a plain shell has no harness env)
printf '{"env":{"SHARED_MEMORY_SELF":"me-mac"}}\n' > "$B/.claude/settings.json"
printf '{"_comment":["copy <owner>/<repo> here"],"shared_memory":{"repo":"~/x","interval":120},"repo_watches":[{"tag":"core","repos":["org/core"],"interval":300}]}\n' > "$B/.claude/rules/collab-watch.json"
out="$(run)"
[ -z "$out" ] && ok "ready instance: silent (placeholders inside _comment do not count, self id from settings)" \
  || bad "ready instance: silent" "'$out'"

# 5 — a PR for this instance arrived in a repo the watch does not poll (all three machines, 2026-10-16)
printf '{"items":{"core#5":{"first":"%s"},"own-brain#2":{"first":"%s"},"old-repo#1":{"first":"2020-01-01"}}}\n' "$TODAY" "$TODAY" > "$B/.claude-state/open-items-seen.json"
out="$(run)"
has "unwatched PR repo named" "does not poll: own-brain" "$out"
hasnt "a watched repo is not named" "core —" "$out"
hasnt "an item older than the window is not named" "old-repo" "$out"

# 6 — broken JSON is a finding, not a crash
printf '{"repo_watches": [' > "$B/.claude/rules/collab-watch.json"
out="$(run)"
has "broken config named" "not valid JSON" "$out"

echo
[ "$fail" -eq 0 ] && echo "test-watch-readiness: all checks passed" || echo "test-watch-readiness: FAILURES"
exit "$fail"
