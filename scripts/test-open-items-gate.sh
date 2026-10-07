#!/usr/bin/env bash
# Fixture test for helpers/open-items-gate.cjs — both directions.
# The must-block case is the incident itself (2026-10-07): the bootup listed open points,
# the first reply said "older requests, nothing new" and named none. Also: a cancelled or
# missing bootup blocks, a later turn and a compaction never do, and the "nothing open" /
# "not checked" / "parked" phrasing works in English built-ins and, as DATA only, German.
# Usage: bash scripts/test-open-items-gate.sh (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
G="$(cd "$(dirname "$0")" && pwd)/../helpers/open-items-gate.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
[ -f "$G" ] || { echo "  FAIL gate missing: $G"; exit 1; }

# OS-3: node opens these paths; a Git-Bash /tmp path would not resolve and every
# must-block case would pass for the wrong reason.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }

BOOT_CMD='/bin/zsh \"$CLAUDE_PROJECT_DIR/core/helpers/session-bootup.sh\"'
boot_ok() { # $1 hookName source, $2 bootup text
  printf '{"attachment":{"type":"hook_success","hookName":"SessionStart:%s","hookEvent":"SessionStart","command":"%s","content":%s},"type":"attachment"}\n' \
    "$1" "$BOOT_CMD" "$(js "$2")"
}
boot_cancel() {
  printf '{"attachment":{"type":"hook_cancelled","hookName":"SessionStart:startup","hookEvent":"SessionStart","command":"%s","durationMs":30024,"timedOut":true},"type":"attachment"}\n' "$BOOT_CMD"
}
user() { printf '{"message":{"role":"user","content":%s}}\n' "$(js "$1")"; }
asst() { printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(js "$1")"; }

check() { # $1 name, $2 transcript file, $3 block|allow, $4 cwd, [$5 stop_hook_active]
  local out
  out="$(printf '{"transcript_path":"%s","stop_hook_active":%s,"cwd":"%s"}' \
    "$(native "$2")" "${5:-false}" "$(native "$4")" | node "$G" 2>&1)"
  if [ "$3" = block ]; then
    case "$out" in *'"decision":"block"'*) ok "$1 blocks";; *) bad "$1 did not block: '$out'";; esac
  else
    [ -z "$out" ] && ok "$1 allows" || bad "$1 blocked wrongly: '$out'"
  fi
}

EN="$T/cwd-en"; mkdir -p "$EN"
DE="$T/cwd-de"; mkdir -p "$DE/.claude/rules"
printf '%s\n' '{"nothing_patterns":["nichts offen"],"failed_patterns":["nicht gepr(ü|ue)ft","gescheitert"],"parked_patterns":["geparkt"]}' \
  > "$DE/.claude/rules/open-items.json"

NL=$'\n'
BLOCK="=== BRAIN BOOTUP CHECK ===${NL}open for us: 2 (+1 parked) — EVERY item goes into the first reply${NL}- [request] 2026-09-05 show-tools/anfrage-td-2026-09-05.md — peer-b: ANFRAGE — !! reported in 3 sessions since 2026-10-01, nothing done yet${NL}- [PR] 2026-10-07 claude-marketplace#61 — someone: pin(td) — first report${NL}- [parked] grandma3-suite#112${NL}=== END BOOTUP ==="

# 1 — the incident: items listed, the reply names none of them.
f="$T/1.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "Brain sauber. 9 aeltere Anfragen, nichts Neues seit letztem Start."; } > "$f"
check "incident reply (names no item)" "$f" block "$EN"

# 2 — every item named (ISO date, PR number, parked word).
f="$T/2.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "Open: request of 2026-09-05 from the workstation; marketplace #61 pin. Parked: grandMA #112."; } > "$f"
check "all items named" "$f" allow "$EN"

# 3 — German date form and German parked word, with the instance file.
f="$T/3.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "Anfrage vom 5.9. (Workstation), PR #61. grandMA geparkt."; } > "$f"
check "German date + parked word via instance data" "$f" allow "$DE"
check "German parked word without instance data" "$f" block "$EN"

# 4 — one item left out.
f="$T/4.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "PR #61 is open. Parked: #112."; } > "$f"
check "one request left out" "$f" block "$EN"

# 5 — the bootup was cancelled by the hook timeout.
f="$T/5.jsonl"; { boot_cancel; user "stand?"; asst "All good."; } > "$f"
check "cancelled bootup" "$f" block "$EN"

# 6 — no bootup record at all, first prompt.
f="$T/6.jsonl"; { user "stand?"; asst "All good."; } > "$f"
check "missing bootup" "$f" block "$EN"

# 7 — bootup from an older core without the block.
f="$T/7.jsonl"; { boot_ok startup "=== BRAIN BOOTUP CHECK ===${NL}open PRs (6 shown): a#1${NL}=== END BOOTUP ==="; user "stand?"; asst "All good."; } > "$f"
check "bootup without open-items block" "$f" block "$EN"

# 8 — second turn: not the first reply any more.
f="$T/8.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "Open: 2026-09-05, #61, parked #112."; user "next"; asst "Done."; } > "$f"
check "second turn" "$f" allow "$EN"

# 9 — compaction is the same session.
f="$T/9.jsonl"; { boot_ok compact "$BLOCK"; user "go on"; asst "Continuing."; } > "$f"
check "compaction" "$f" allow "$EN"

# 10 — re-issued answer.
f="$T/1.jsonl"
check "stop_hook_active" "$f" allow "$EN" true

# 11 — hook feedback and task notifications are not operator prompts.
f="$T/11.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "Short."; user "Stop hook feedback: something"; asst "Longer."; user "<task-notification>x</task-notification>"; asst "Still nothing."; } > "$f"
check "feedback/notification turns stay inside the first turn" "$f" block "$EN"

# 12 — nothing open: must be said.
NOTHING="open for us: 0 — EVERY item goes into the first reply${NL}- nothing open (requests and PRs both read)"
f="$T/12a.jsonl"; { boot_ok startup "$NOTHING"; user "stand?"; asst "Nothing open. Brain clean."; } > "$f"
check "nothing open, said" "$f" allow "$EN"
f="$T/12b.jsonl"; { boot_ok startup "$NOTHING"; user "stand?"; asst "Brain clean."; } > "$f"
check "nothing open, not said" "$f" block "$EN"
f="$T/12c.jsonl"; { boot_ok startup "$NOTHING"; user "stand?"; asst "Nichts offen."; } > "$f"
check "nothing open in German via instance data" "$f" allow "$DE"

# 13 — a source that could not be read must be reported as such.
FAILED="open for us: 0 — EVERY item goes into the first reply${NL}!! open for us: PR search NOT checked — this is not 'nothing open'"
f="$T/13a.jsonl"; { boot_ok startup "$FAILED"; user "stand?"; asst "Brain clean."; } > "$f"
check "failed source not mentioned" "$f" block "$EN"
f="$T/13b.jsonl"; { boot_ok startup "$FAILED"; user "stand?"; asst "PR search not checked (offline)."; } > "$f"
check "failed source mentioned" "$f" allow "$EN"

# 14 — a PR number that only PREFIXES another must not count (#6 vs #61).
f="$T/14.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "2026-09-05 request, PR #610, parked."; } > "$f"
check "#610 does not name #61" "$f" block "$EN"

[ "$fail" = 0 ] && echo "open-items-gate: all cases pass" || { echo "open-items-gate: FAILURES"; exit 1; }
