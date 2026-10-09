#!/usr/bin/env bash
# Fixture test for helpers/open-items-gate.cjs — both directions.
# The must-block case is the incident itself (2026-10-07): the bootup listed open points,
# the first reply said "older requests, nothing new" and named none. The required form
# (operator, same day): "n I can handle — shall I?" (one OK) + "n need you" (up to three
# named, more offered), repeats said. Also: an unclassified item blocks until the agent's
# class file holds it; a cancelled or missing bootup blocks; a later turn and a compaction
# never do; stoppen-gate leaves exactly the opening question alone — and only that one.
# German phrasing grips only as instance DATA (one case runs it without the file).
# Usage: bash scripts/test-open-items-gate.sh (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
D="$(cd "$(dirname "$0")" && pwd)/../helpers"
G="$D/open-items-gate.cjs"
SG="$D/stoppen-gate.cjs"
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

check() { # $1 name, $2 transcript, $3 block|allow, $4 cwd, [$5 stop_hook_active], [$6 gate]
  local out
  out="$(printf '{"transcript_path":"%s","stop_hook_active":%s,"cwd":"%s"}' \
    "$(native "$2")" "${5:-false}" "$(native "$4")" | node "${6:-$G}" 2>&1)"
  if [ "$3" = block ]; then
    case "$out" in *'"decision":"block"'*) ok "$1 blocks";; *) bad "$1 did not block: '$out'";; esac
  else
    [ -z "$out" ] && ok "$1 allows" || bad "$1 blocked wrongly: '$out'"
  fi
}

EN="$T/cwd-en"; mkdir -p "$EN"
DE="$T/cwd-de"; mkdir -p "$DE/.claude/rules"
printf '%s\n' '{"nothing_patterns":["nichts offen"],"failed_patterns":["nicht gepr(ü|ue)ft","gescheitert"],"parked_patterns":["geparkt"],"offer_patterns":["\\bsoll ich\\b[^?\\n]{0,160}\\?"],"repeat_patterns":["bereits .{0,40}gemeldet","schon .{0,40}gemeldet","weiterhin offen"],"generic_words":["anfrage"],"goahead_patterns":["durchziehen"]}' \
  > "$DE/.claude/rules/open-items.json"

NL=$'\n'
H1="- [request|human] 2026-09-05 show-tools/anfrage-td-2026-09-05.md — peer-b: ANFRAGE — !! reported in 3 sessions since 2026-10-01, nothing done yet (circle E)"
H2="- [request|human] 2026-09-08 event-network/anfrage-bridge-2026-09-08.md — peer-c: Rueckfrage — first report (addressed to a person)"
A1="- [PR|ai] 2026-10-07 claude-marketplace#61 — someone: pin(td) — first report (PR: review/merge is agent work)"
A2="- [request|ai] 2026-09-13 core/anfrage-fixtures-2026-09-13.md — peer-d: ANFRAGE — first report (circle C)"
BLOCK="=== BRAIN BOOTUP CHECK ===${NL}open for us: 4 — ai 2 · human 2 · unclassified 0 (+1 parked)${NL}${H1}${NL}${H2}${NL}${A1}${NL}${A2}${NL}- [parked] grandma3-suite#112${NL}=== END BOOTUP ==="

GOOD_EN="2 items I can handle myself (the marketplace pin, an answer on the fixtures) — shall I go ahead?
2 need you:
- 2026-09-05 the workstation needs the TD work split — already reported, still open
- 2026-09-08 a question about the bridge device
grandMA stays parked (#112)."
GOOD_DE="2 Punkte kann ich selbst beantworten — soll ich?
2 Anliegen brauchen dich:
- 5.9. die Workstation braucht die TD-Arbeitsteilung — bereits mehrfach gemeldet
- 8.9. Rueckfrage zum Brueckengeraet
grandMA bleibt geparkt."

# 1 — the incident: items listed, the reply names none of them.
f="$T/1.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "Brain clean. 9 older requests, nothing new since the last start."; } > "$f"
check "incident reply" "$f" block "$EN"

# 2 — the required form, English built-ins.
f="$T/2.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_EN"; } > "$f"
check "required form (EN)" "$f" allow "$EN"

# 3 — the same form in German: only through instance data.
f="$T/3.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_DE"; } > "$f"
check "required form (DE) with instance data" "$f" allow "$DE"
check "required form (DE) without instance data" "$f" block "$EN"

# 4 — an operator item left out.
f="$T/4.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "${GOOD_EN/- 2026-09-08 a question about the bridge device/}"; } > "$f"
check "operator item left out" "$f" block "$EN"

# 5 — no question for the items the agent could handle.
f="$T/5.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "${GOOD_EN/ — shall I go ahead?/.}"; } > "$f"
check "no opening question" "$f" block "$EN"

# 6 — repeats not said.
f="$T/6.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "${GOOD_EN/ — already reported, still open/}"; } > "$f"
check "repeat not said" "$f" block "$EN"

# 7 — more than three operator items: count + offer, no list needed.
MANY="open for us: 5 — ai 0 · human 5 · unclassified 0"
for d in 01 02 03 04 05; do MANY="${MANY}${NL}- [request|human] 2026-09-${d} ops/req-${d}.md — peer-b: x — first report"; done
f="$T/7a.jsonl"; { boot_ok startup "$MANY"; user "stand?"; asst "5 items need you directly — shall I list them?"; } > "$f"
check "more than three: count + offer" "$f" allow "$EN"
f="$T/7b.jsonl"; { boot_ok startup "$MANY"; user "stand?"; asst "5 items need you directly."; } > "$f"
check "more than three: no offer" "$f" block "$EN"

# 8 — an unclassified item blocks until the class file holds it.
Q="open for us: 1 — ai 0 · human 0 · unclassified 1${NL}- [request|?] 2026-09-06 event-network/anfrage-net-2026-09-06.md — peer-c: ANFRAGE — first report"
f="$T/8.jsonl"; { boot_ok startup "$Q"; user "stand?"; asst "1 needs you: 2026-09-06 the network definition."; } > "$f"
check "unclassified item" "$f" block "$EN"
CL="$T/cwd-cls"; mkdir -p "$CL/.claude-state"
printf '%s\n' '{"anfrage-net-2026-09-06.md":{"class":"human","why":"needs the operator net definition"}}' > "$CL/.claude-state/open-items-class.json"
check "classified via the class file" "$f" allow "$CL"

# 9 — the bootup did not arrive.
f="$T/9a.jsonl"; { boot_cancel; user "stand?"; asst "All good."; } > "$f"
check "cancelled bootup" "$f" block "$EN"
f="$T/9b.jsonl"; { user "stand?"; asst "All good."; } > "$f"
check "missing bootup" "$f" block "$EN"
f="$T/9c.jsonl"; { boot_ok startup "=== BRAIN BOOTUP CHECK ===${NL}open PRs (6 shown): a#1${NL}=== END BOOTUP ==="; user "stand?"; asst "All good."; } > "$f"
check "bootup without open-items block" "$f" block "$EN"

# 10 — later turns, compaction, re-issue, non-prompt user records.
f="$T/10a.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_EN"; user "next"; asst "Done."; } > "$f"
check "second turn" "$f" allow "$EN"
f="$T/10b.jsonl"; { boot_ok compact "$BLOCK"; user "go on"; asst "Continuing."; } > "$f"
check "compaction" "$f" allow "$EN"
check "stop_hook_active" "$T/1.jsonl" allow "$EN" true
f="$T/10c.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "Short."; user "Stop hook feedback: x"; asst "Longer."; user "<task-notification>x</task-notification>"; asst "Still nothing."; } > "$f"
check "feedback/notification turns stay inside the first turn" "$f" block "$EN"

# 11 — nothing open; a failed source.
NOTHING="open for us: 0 — ai 0 · human 0 · unclassified 0${NL}- nothing open (requests and PRs both read)"
f="$T/11a.jsonl"; { boot_ok startup "$NOTHING"; user "stand?"; asst "Nothing open. Brain clean."; } > "$f"
check "nothing open, said" "$f" allow "$EN"
f="$T/11b.jsonl"; { boot_ok startup "$NOTHING"; user "stand?"; asst "Brain clean."; } > "$f"
check "nothing open, not said" "$f" block "$EN"
f="$T/11c.jsonl"; { boot_ok startup "$NOTHING"; user "stand?"; asst "Nichts offen."; } > "$f"
check "nothing open in German via instance data" "$f" allow "$DE"
FAILED="open for us: 0 — ai 0 · human 0 · unclassified 0${NL}!! open for us: PR search NOT checked — this is not 'nothing open'"
f="$T/11d.jsonl"; { boot_ok startup "$FAILED"; user "stand?"; asst "Brain clean."; } > "$f"
check "failed source not said" "$f" block "$EN"
f="$T/11e.jsonl"; { boot_ok startup "$FAILED"; user "stand?"; asst "PR search not checked (offline)."; } > "$f"
check "failed source said" "$f" allow "$EN"

# 12 — a PR number that only PREFIXES another must not count (#61 vs #610).
H3="- [PR|human] 2026-10-07 claude-marketplace#61 — someone: pin — first report"
P="open for us: 1 — ai 0 · human 1 · unclassified 0${NL}${H3}"
f="$T/12.jsonl"; { boot_ok startup "$P"; user "stand?"; asst "1 needs you: PR #610."; } > "$f"
check "#610 does not name #61" "$f" block "$EN"

# 13 — stoppen-gate: the opening question passes, a closing question elsewhere does not.
check "stoppen-gate leaves the opening question alone" "$T/2.jsonl" allow "$EN" false "$SG"
f="$T/13.jsonl"; { boot_ok startup "$P"; user "stand?"; asst "1 needs you: PR #61. Shall I start on the refactor?"; } > "$f"
check "stoppen-gate still judges when no opening question is due" "$f" block "$EN" false "$SG"

# 14 — a request named by its AGE counts (measured false fire 2026-10-09: all items named
# with "open for 32 days", none with a date). A wrong age does not.
AGE=$(node -e 'console.log(Math.round((Date.now()-new Date("2026-09-05T12:00:00").getTime())/86400000))')
H4="- [request|human] 2026-09-05 ops/x-2026-09-05.md — peer-b: ANFRAGE — first report"
P4="open for us: 1 — ai 0 · human 1 · unclassified 0${NL}${H4}"
f="$T/14a.jsonl"; { boot_ok startup "$P4"; user "stand?"; asst "1 needs you: peer-b's request, open for $AGE days."; } > "$f"
check "request named by its age" "$f" allow "$EN"
f="$T/14b.jsonl"; { boot_ok startup "$P4"; user "stand?"; asst "1 needs you: peer-b's request, open for $((AGE + 10)) days."; } > "$f"
check "a wrong age names nothing" "$f" block "$EN"

# 15 — a request named by its topic words in plain language, no date, no file name.
H5="- [request|human] 2026-09-06 show-tools/anfrage-arbeitsteilung-touchdesigner-2026-09-06.md — peer-b: ANFRAGE — first report"
P5="open for us: 1 — ai 0 · human 1 · unclassified 0${NL}${H5}"
f="$T/15a.jsonl"; { boot_ok startup "$P5"; user "stand?"; asst "1 needs you: how the TouchDesigner Arbeitsteilung is split."; } > "$f"
check "request named by its topic words" "$f" allow "$EN"
f="$T/15b.jsonl"; { boot_ok startup "$P5"; user "stand?"; asst "1 needs you: an Anfrage from peer-b about TouchDesigner."; } > "$f"
check "one topic word plus the generic kind (instance data) is not enough" "$f" block "$DE"

# 16 — items waiting on others or a date need no relay and no opening question.
W="open for us: 0 — ai 0 · human 0 · unclassified 0 (+1 waiting on others or a date)${NL}- [PR|wait] 2026-09-28 suite-x#13 — peer: t — waiting on peer: we reviewed or commented after the last commit"
f="$T/16.jsonl"; { boot_ok startup "$W"; user "stand?"; asst "Brain clean."; } > "$f"
check "waiting items need no relay" "$f" allow "$EN"
f="$T/16b.jsonl"; { boot_ok startup "$W"; user "stand?"; asst "Brain clean. Shall I start on the refactor?"; } > "$f"
check "a waiting item does not own the closing question" "$f" block "$EN" false "$SG"

# 17 — stoppen-gate leaves a question alone that a bootup rule ORDERS ("ask the operator"),
# on any turn; any other closing question is still judged.
BS="${P}${NL}!! brain-scan DUE: latest report 9d ago (due after 7d) — ask the operator, then run it in this session"
f="$T/17a.jsonl"; { boot_ok startup "$BS"; user "stand?"; asst "1 needs you: PR #61."; user "ok"; asst "Done. Shall I start the brain scan now?"; } > "$f"
check "stoppen-gate leaves the ordered brain-scan question alone" "$f" allow "$EN" false "$SG"
f="$T/17b.jsonl"; { boot_ok startup "$BS"; user "stand?"; asst "1 needs you: PR #61."; user "ok"; asst "Done. Shall I start the refactor now?"; } > "$f"
check "stoppen-gate judges a question the rule did not order" "$f" block "$EN" false "$SG"
f="$T/17c.jsonl"; { boot_ok startup "$P"; user "stand?"; asst "1 needs you: PR #61."; user "ok"; asst "Done. Shall I start the brain scan now?"; } > "$f"
check "no ordering bootup line, no exception" "$f" block "$EN" false "$SG"

# 18 — the operator's prompt already ordered the work (measured 2026-10-09, German go-ahead
# "alles durchziehen"): the count and the repeats are still said, the shall-I question is moot.
GO="8 Punkte kann ich selbst abhandeln, die Freigabe liegt mit deinem Auftrag vor. Davon 5 schon in bis zu 6 Sessions gemeldet. 2 brauchen dich: 2026-09-05 TD-Arbeitsteilung, 2026-09-08 Brueckengeraet. grandMA bleibt geparkt."
f="$T/18a.jsonl"; { boot_ok startup "$BLOCK"; user "bitte alles durchziehen"; asst "${GO/8 Punkte/2 Punkte}"; } > "$f"
check "go-ahead in the prompt makes the question moot (instance data)" "$f" allow "$DE"
f="$T/18b.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "${GO/8 Punkte/2 Punkte}"; } > "$f"
check "no go-ahead, no question" "$f" block "$DE"
f="$T/18c.jsonl"; { boot_ok startup "$BLOCK"; user "go ahead and handle everything"; asst "2 items I can handle, 2 need you: 2026-09-05 the TD split (already reported, still open), 2026-09-08 the bridge. grandMA stays parked."; } > "$f"
check "English go-ahead built in" "$f" allow "$EN"

[ "$fail" = 0 ] && echo "open-items-gate: all cases pass" || { echo "open-items-gate: FAILURES"; exit 1; }
