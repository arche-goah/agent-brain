#!/usr/bin/env bash
# Fixture for scripts/transcript-archive.sh against a fake config dir. Both directions:
# a complete archive is written, opens, and holds the same bytes; a destination inside a
# git work tree is refused (the archive must never sit one `git add` from a remote); a
# missing source or destination fails loudly instead of producing an empty archive.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/transcript-archive.sh"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1 — $2"; fails=$((fails + 1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/cfg/projects/p-one/sub" "$T/cfg/projects/p-two" "$T/out" "$T/out-empty"
printf '{"a":1}\n' > "$T/cfg/projects/p-one/s1.jsonl"
printf '{"b":2}\n' > "$T/cfg/projects/p-one/sub/agent.jsonl"
printf '{"c":3}\n' > "$T/cfg/projects/p-two/s2.jsonl"
run() { CLAUDE_CONFIG_DIR="$T/cfg" bash "$S" "$@" 2>&1; }

echo "complete archive"
out="$(run "$T/out")"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0" || bad "exit 0" "rc=$rc: $out"
case "$out" in *"3 files in the archive / 3 in the source"*) ok "counts compared" ;; *) bad "counts compared" "$out" ;; esac
arc="$(ls "$T/out"/claude-transcripts-*.tar.gz 2>/dev/null | head -1)"
if [ -n "$arc" ]; then
  mkdir -p "$T/x" && tar -xzf "$arc" -C "$T/x"
  if cmp -s "$T/x/projects/p-one/sub/agent.jsonl" "$T/cfg/projects/p-one/sub/agent.jsonl"; then
    ok "nested file restored byte-identical"
  else
    bad "nested file restored byte-identical" "content differs or missing"
  fi
else
  bad "archive file named claude-transcripts-<stamp>.tar.gz" "none in $T/out"
fi

echo "negative control: destination inside a git work tree"
mkdir -p "$T/repo" && git -C "$T/repo" init -q
out="$(run "$T/repo")"; rc=$?
[ "$rc" -eq 3 ] && ok "refused with exit 3" || bad "refused with exit 3" "rc=$rc: $out"
n="$(ls "$T/repo" | wc -l | tr -d ' ')"
[ "$n" -eq 0 ] && ok "nothing written into the repo" || bad "nothing written into the repo" "$n entries"

echo "loud failures"
out="$(run)"; rc=$?
[ "$rc" -eq 3 ] && ok "no destination: usage, exit 3" || bad "no destination: usage, exit 3" "rc=$rc"
out="$(run "$T/nope")"; rc=$?
[ "$rc" -eq 1 ] && ok "missing destination: exit 1" || bad "missing destination: exit 1" "rc=$rc"
out="$(CLAUDE_CONFIG_DIR="$T/no-cfg" bash "$S" "$T/out-empty" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "missing source: exit 1" || bad "missing source: exit 1" "rc=$rc"
n="$(ls "$T/out-empty" | wc -l | tr -d ' ')"
[ "$n" -eq 0 ] && ok "missing source writes no archive" || bad "missing source writes no archive" "$n entries"

echo
if [ "$fails" -eq 0 ]; then echo "test-transcript-archive: all checks passed"; exit 0; fi
echo "test-transcript-archive: $fails check(s) FAILED"; exit 1
