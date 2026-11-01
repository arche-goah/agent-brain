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
H1="- [request|human] 2026-09-05 widget-suite/anfrage-ui-2026-09-05.md — peer-b: ANFRAGE — !! reported in 3 sessions since 2026-10-01, nothing done yet (circle E)"
H2="- [request|human] 2026-09-08 demo-area/anfrage-bridge-2026-09-08.md — peer-c: Rueckfrage — first report (addressed to a person)"
A1="- [PR|ai] 2026-10-07 example-market#61 — someone: pin(widget) — first report (PR: review/merge is agent work)"
A2="- [request|ai] 2026-09-13 core/anfrage-fixtures-2026-09-13.md — peer-d: ANFRAGE — first report (circle C)"
BLOCK="=== BRAIN BOOTUP CHECK ===${NL}open for us: 4 — ai 2 · human 2 · unclassified 0 (+1 parked)${NL}${H1}${NL}${H2}${NL}${A1}${NL}${A2}${NL}- [parked] grandma3-suite#112${NL}=== END BOOTUP ==="

GOOD_EN="2 items I can handle myself (the marketplace pin, an answer on the fixtures) — shall I go ahead?
2 need you:
- 2026-09-05 the workstation needs the UI layout — already reported, still open
- 2026-09-08 a question about the bridge device
grandMA stays parked (#112)."
GOOD_DE="2 Punkte kann ich selbst beantworten — soll ich?
2 Anliegen brauchen dich:
- 5.9. die Workstation braucht das UI-Layout — bereits mehrfach gemeldet
- 8.9. Rueckfrage zum Brueckengeraet
grandMA bleibt geparkt."

# 1 — the incident: items listed, the reply names none of them.
f="$T/1.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "Brain clean. 9 older requests, nothing new since the last start."; } > "$f"
check "incident reply" "$f" block "$EN"

# 2 — the required form, English built-ins.
f="$T/2.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_EN"; } > "$f"
check "required form (EN)" "$f" allow "$EN"
# a skill loaded through the Skill tool before the reply is no second prompt (2026-10-20): it
# counted as one, the turn read as "not the first" and the check fell silent
SKILL_REC='{"isMeta":true,"sourceToolUseID":"toolu_x","message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: x"}]}}'
f="$T/2s.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; echo "$SKILL_REC"; asst "Brain clean. 9 older requests, nothing new."; } > "$f"
check "incident reply after a loaded skill" "$f" block "$EN"
f="$T/2t.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; echo "$SKILL_REC"; asst "$GOOD_EN"; } > "$f"
check "required form after a loaded skill" "$f" allow "$EN"

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
Q="open for us: 1 — ai 0 · human 0 · unclassified 1${NL}- [request|?] 2026-09-06 demo-area/anfrage-net-2026-09-06.md — peer-c: ANFRAGE — first report"
f="$T/8.jsonl"; { boot_ok startup "$Q"; user "stand?"; asst "1 needs you: 2026-09-06 the network definition."; } > "$f"
check "unclassified item" "$f" block "$EN"
CL="$T/cwd-cls"; mkdir -p "$CL/.claude-state"
printf '%s\n' '{"anfrage-net-2026-09-06.md":{"class":"human","why":"needs the operator net definition"}}' > "$CL/.claude-state/open-items-class.json"
check "classified via the class file" "$f" allow "$CL"

# 8b — an unclassified LOG entry: the block names its id (`<area>/LOG@<date>#<n>`), the key
# --classify takes, not "LOG <date> <sender>", which covered every entry of that sender that day.
QL="open for us: 1 — ai 0 · human 0 · unclassified 1${NL}- [request|?] 2026-10-07 core/LOG@2026-10-07#1 — peer-b: AN inst-a: first note — first report"
f="$T/8b.jsonl"; { boot_ok startup "$QL"; user "stand?"; asst "1 item."; } > "$f"
out8b="$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$(native "$f")" "$(native "$EN")" | node "$G" 2>&1)"
case "$out8b" in
  *'core/LOG@2026-10-07#1'*) ok "unclassified LOG entry is named by its id" ;;
  *) bad "unclassified LOG entry not named by its id: '$out8b'" ;;
esac
# 8c — ...and a class stored under that id (what --classify writes) satisfies the gate.
# Measured 2026-10-12 (Windows instance): classified via the script, the gate still read the
# bare ref and blocked the first reply. NEGATIVE: a class for the same sender's other entry
# that day leaves this one `?`.
f="$T/8c.jsonl"; { boot_ok startup "$QL"; user "stand?"; asst "1 needs you: the 2026-10-07 note from peer-b."; } > "$f"
CLL="$T/cwd-cls-log"; mkdir -p "$CLL/.claude-state"
printf '%s\n' '{"core/LOG@2026-10-07#1":{"class":"human","why":"asks the operator"}}' > "$CLL/.claude-state/open-items-class.json"
check "LOG entry classified under its id" "$f" allow "$CLL"
CLX="$T/cwd-cls-log-other"; mkdir -p "$CLX/.claude-state"
printf '%s\n' '{"core/LOG@2026-10-07#2":{"class":"human","why":"asks the operator"}}' > "$CLX/.claude-state/open-items-class.json"
check "a class for the other entry of that day leaves this one unclassified" "$f" block "$CLX"

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
# No GitHub owner known (open-items.py, 2026-10-31): a neutral note, no failed source — the
# reply owes it nothing, so the start cannot carry a demand no action clears.
NOOWNER="open for us: 0 — ai 0 · human 0 · unclassified 0${NL}note: open PRs not looked for — no GitHub owner is known for this brain"
f="$T/11f.jsonl"; { boot_ok startup "$NOOWNER"; user "stand?"; asst "Brain clean."; } > "$f"
check "no owner: the note demands nothing" "$f" allow "$EN"

# 12 — a PR number that only PREFIXES another must not count (#61 vs #610).
H3="- [PR|human] 2026-10-07 example-market#61 — someone: pin — first report"
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
H5="- [request|human] 2026-09-06 widget-suite/anfrage-renderer-handover-2026-09-06.md — peer-b: ANFRAGE — first report"
P5="open for us: 1 — ai 0 · human 1 · unclassified 0${NL}${H5}"
f="$T/15a.jsonl"; { boot_ok startup "$P5"; user "stand?"; asst "1 needs you: who takes the renderer handover."; } > "$f"
check "request named by its topic words" "$f" allow "$EN"
f="$T/15b.jsonl"; { boot_ok startup "$P5"; user "stand?"; asst "1 needs you: an Anfrage from peer-b about the renderer."; } > "$f"
check "one topic word plus the generic kind (instance data) is not enough" "$f" block "$DE"

# 16 — items waiting on others or a date need no relay and no opening question.
W="open for us: 0 — ai 0 · human 0 · unclassified 0 (+1 waiting on others or a date)${NL}- [PR|wait] 2026-09-28 suite-x#13 — peer: t — waiting on peer: we reviewed or commented after the last commit"
f="$T/16.jsonl"; { boot_ok startup "$W"; user "stand?"; asst "Brain clean."; } > "$f"
check "waiting items need no relay" "$f" allow "$EN"
f="$T/16b.jsonl"; { boot_ok startup "$W"; user "stand?"; asst "Brain clean. Shall I start on the refactor?"; } > "$f"
check "a waiting item does not own the closing question" "$f" block "$EN" false "$SG"

# 17 — stoppen-gate leaves a question alone that a bootup rule ORDERS ("ask the operator"),
# on any turn; any other closing question is still judged.
BS="${P}${NL}!! brain-scan DUE: latest report 15d ago (due after 14d) — ask the operator, then run it in this session"
f="$T/17a.jsonl"; { boot_ok startup "$BS"; user "stand?"; asst "1 needs you: PR #61."; user "ok"; asst "Done. Shall I start the brain scan now?"; } > "$f"
check "stoppen-gate leaves the ordered brain-scan question alone" "$f" allow "$EN" false "$SG"
f="$T/17b.jsonl"; { boot_ok startup "$BS"; user "stand?"; asst "1 needs you: PR #61."; user "ok"; asst "Done. Shall I start the refactor now?"; } > "$f"
check "stoppen-gate judges a question the rule did not order" "$f" block "$EN" false "$SG"
f="$T/17c.jsonl"; { boot_ok startup "$P"; user "stand?"; asst "1 needs you: PR #61."; user "ok"; asst "Done. Shall I start the brain scan now?"; } > "$f"
check "no ordering bootup line, no exception" "$f" block "$EN" false "$SG"

# 18 — the operator's prompt already ordered the work (measured 2026-10-09, German go-ahead
# "alles durchziehen"): the count and the repeats are still said, the shall-I question is moot.
GO="8 Punkte kann ich selbst abhandeln, die Freigabe liegt mit deinem Auftrag vor. Davon 5 schon in bis zu 6 Sessions gemeldet. 2 brauchen dich: 2026-09-05 UI-Layout, 2026-09-08 Brueckengeraet. grandMA bleibt geparkt."
f="$T/18a.jsonl"; { boot_ok startup "$BLOCK"; user "bitte alles durchziehen"; asst "${GO/8 Punkte/2 Punkte}"; } > "$f"
check "go-ahead in the prompt makes the question moot (instance data)" "$f" allow "$DE"
f="$T/18b.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "${GO/8 Punkte/2 Punkte}"; } > "$f"
check "no go-ahead, no question" "$f" block "$DE"
f="$T/18c.jsonl"; { boot_ok startup "$BLOCK"; user "go ahead and handle everything"; asst "2 items I can handle, 2 need you: 2026-09-05 the UI layout (already reported, still open), 2026-09-08 the bridge. grandMA stays parked."; } > "$f"
check "English go-ahead built in" "$f" allow "$EN"
# An autonomous order is a go-ahead (autonomous-mode.cjs): the offer question would be the stop
# the rule forbids. Same reply under "stand?" blocks (18b-shape discriminator in English).
f="$T/18d.jsonl"; { boot_ok startup "$BLOCK"; user "work through the list autonomously"; asst "2 items I can handle, 2 need you: 2026-09-05 the UI layout (already reported, still open), 2026-09-08 the bridge. grandMA stays parked."; } > "$f"
check "an autonomous order needs no offer question" "$f" allow "$EN"
f="$T/18e.jsonl"; { boot_ok startup "$BLOCK"; user "status?"; asst "2 items I can handle, 2 need you: 2026-09-05 the UI layout (already reported, still open), 2026-09-08 the bridge. grandMA stays parked."; } > "$f"
check "the same reply without the order still needs the question" "$f" block "$EN"

# Wake-up of a parked domain (operator order 2026-10-11): an operator item like any other —
# the first reply must name it; leaving it out blocks.
W1="- [wake|human] 2026-10-20 lightdesk — peer-x: parked domain lightdesk: peer-x is active again (PR desk-suite#9, 1 move(s) since 2026-09-18) - ask the operator whether to unpark — first report (the party that paused it moved again)"
WB="=== BRAIN BOOTUP CHECK ===${NL}open for us: 1 — ai 0 · human 1 · unclassified 0 (+1 parked)${NL}${W1}${NL}- [parked] desk-suite#3${NL}=== END BOOTUP ==="
f="$T/19a.jsonl"; { boot_ok startup "$WB"; user "stand?"; asst "1 point needs you: the parked lightdesk domain is active again on the other side - unpark it? The rest stays parked."; } > "$f"
check "wake-up item named" "$f" allow "$EN"
f="$T/19b.jsonl"; { boot_ok startup "$WB"; user "stand?"; asst "1 point needs you. Everything else stays parked."; } > "$f"
check "wake-up item left out" "$f" block "$EN"

# 19c — an open work-ledger entry (open-items.py ledgers(), 2026-10-25): an operator item must be
# named like any other; before, the gate skipped the line and a reply leaving it out passed.
L1="- [ledger|human] 2026-10-11 ipc-remeasure — derived: Remeasure the ipc folders with a deviating desk variable — first report (a decision in the ledger)"
L2="- [ledger|human]  pick-name — operator: Pick a name for the wizard — first report (a decision in the ledger)"
LB="=== BRAIN BOOTUP CHECK ===${NL}open for us: 2 — ai 0 · human 2 · unclassified 0${NL}${L1}${NL}${L2}${NL}=== END BOOTUP ==="
f="$T/19c.jsonl"; { boot_ok startup "$LB"; user "stand?"; asst "2 points need you: the ipc remeasure from 2026-10-11, and a name for the wizard."; } > "$f"
check "ledger items named (dated and undated)" "$f" allow "$EN"
f="$T/19d.jsonl"; { boot_ok startup "$LB"; user "stand?"; asst "2 points need you: the ipc remeasure from 2026-10-11."; } > "$f"
check "undated ledger item left out" "$f" block "$EN"

# 20 — a standing approval (full-audit 2026-10-15, Windows instance): the operator approved the
# item's class once for good, so the reply reports it handled instead of asking. Asking anyway
# is not wrong here; leaving it out is. An ai item WITHOUT such a class still needs the question.
S1="- [request|standing] 2026-10-14 core/request-mine-2026-10-14.md — peer-b: check the fixture run — first report (standing approval 'requests to this machine', granted 2026-10-11)"
SG1="- standing approval — handle these, then report what was done (no question needed):"
SB="open for us: 1 — ai 0 · human 0 · unclassified 0 · standing 1${NL}${SG1}${NL}${S1}"
f="$T/20a.jsonl"; { boot_ok startup "$SB"; user "stand?"; asst "1 request handled under the standing approval: the fixture run is checked and answered."; } > "$f"
check "standing item reported as handled" "$f" allow "$EN"
f="$T/20b.jsonl"; { boot_ok startup "$SB"; user "stand?"; asst "1 request I can handle myself — shall I go ahead?"; } > "$f"
check "standing item asked about anyway" "$f" allow "$EN"
f="$T/20c.jsonl"; { boot_ok startup "$SB"; user "stand?"; asst "Brain clean."; } > "$f"
check "standing item left out" "$f" block "$EN"
f="$T/20d.jsonl"; { boot_ok startup "$SB"; user "stand?"; asst "1 Anfrage unter der stehenden Freigabe erledigt."; } > "$f"
check "standing item handled, German word only via instance data" "$f" block "$EN"
DS="$T/cwd-de-st"; mkdir -p "$DS/.claude/rules"
printf '%s\n' '{"handled_patterns":["\\berledigt\\b"]}' > "$DS/.claude/rules/open-items.json"
check "standing item handled, German word with instance data" "$f" allow "$DS"
SM="open for us: 2 — ai 1 · human 0 · unclassified 0 · standing 1${NL}${A2}${NL}${SG1}${NL}${S1}"
f="$T/20e.jsonl"; { boot_ok startup "$SM"; user "stand?"; asst "1 request handled under the standing approval (the fixture run). 1 more I could answer."; } > "$f"
check "ai item without a standing class, no question" "$f" block "$EN"
f="$T/20f.jsonl"; { boot_ok startup "$SM"; user "stand?"; asst "1 request handled under the standing approval (the fixture run). 1 more I can answer myself — shall I?"; } > "$f"
check "ai item asked, standing item reported" "$f" allow "$EN"
# Standing PRs folded into one line (open-items.py, 2026-10-28): each number is still an item,
# so the count the reply must carry is the number of PRs, not of lines.
SF="open for us: 6 — ai 0 · human 0 · unclassified 0 · standing 6${NL}${SG1}${NL}- [PR-standing] 6 PRs: core#1, core#2, core#3, core#4, core#5, suite-x#6 — first report"
f="$T/20g.jsonl"; { boot_ok startup "$SF"; user "stand?"; asst "6 PRs handled under the standing approval: CI watched, reviews answered."; } > "$f"
check "folded standing PRs: count of PRs reported" "$f" allow "$EN"
f="$T/20h.jsonl"; { boot_ok startup "$SF"; user "stand?"; asst "1 line handled under the standing approval."; } > "$f"
check "folded standing PRs: count of lines is not the count (control)" "$f" block "$EN"
# Only ai and unclassified items own the opening question; a standing item does not, so
# stoppen-gate judges a closing question after it as anywhere else.
check "stoppen-gate: a standing item does not own the opening question" "$T/20b.jsonl" block "$EN" false "$SG"

# 21 — the opening question asked through the question tool (operator rule 2026-10-15:
# decisions go through AskUserQuestion). Measured 2026-10-18 on the Windows instance: the
# first reply asked "shall I?" only inside the tool call, the operator answered, and the gate
# blocked twice because it read text blocks only. The tool's answer arrives as a tool_result
# and is no new prompt. Negative control: the same words inside another tool do not count.
ask() { # $1 tool name, $2 question
  printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"%s","input":{"questions":[{"question":%s}]}}]}}\n' "$1" "$(js "$2")"
}
answered() { printf '{"message":{"role":"user","content":[{"type":"tool_result","content":"Yes"}]}}\n'; }
NOQ="${GOOD_EN/ — shall I go ahead?/.}"
f="$T/21a.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$NOQ"; ask AskUserQuestion "2 items I can handle myself — shall I go ahead?"; answered; } > "$f"
check "opening question through the question tool" "$f" allow "$EN"
f="$T/21b.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$NOQ"; ask SomeOtherTool "2 items I can handle myself — shall I go ahead?"; answered; } > "$f"
check "same words inside another tool (control)" "$f" block "$EN"

# 22 — a bootup over the harness limit: the transcript keeps a 2 KB preview and names the file
# holding the whole output (measured 2026-10-22 on the second macOS instance, 10.3 KB bootup:
# "Missing: open-items block" at every turn end, no reply could satisfy it). The gate reads the
# named file. Negative control: a named file that is gone leaves the preview — and blocks.
PF="$T/persisted-bootup.txt"; printf '%s\n' "$BLOCK" > "$PF"
PREVIEW="<persisted-output> Output too large (10.3KB). Full output saved to: $(native "$PF") Preview (first 2KB): === BRAIN BOOTUP CHECK ===${NL}git: branch=main"
f="$T/22a.jsonl"; { boot_ok startup "$PREVIEW"; user "stand?"; asst "$GOOD_EN"; } > "$f"
check "persisted bootup: the named file is read, the required form passes" "$f" allow "$EN"
f="$T/22b.jsonl"; { boot_ok startup "$PREVIEW"; user "stand?"; asst "Brain clean. 9 older requests, nothing new."; } > "$f"
check "persisted bootup: the incident reply still blocks" "$f" block "$EN"
# ...and a path with a space in it (a Windows profile name — measured 2026-10-25 on the Windows
# instance: `\S+` cut the path at the space, the file was never read). Preview on the next line.
PS="$T/profile name/persisted-bootup.txt"; mkdir -p "$T/profile name"; printf '%s\n' "$BLOCK" > "$PS"
PREVIEW_SPACE="<persisted-output> Output too large (13.4KB). Full output saved to: $(native "$PS")${NL}Preview (first 2KB): === BRAIN BOOTUP CHECK ==="
f="$T/22d.jsonl"; { boot_ok startup "$PREVIEW_SPACE"; user "stand?"; asst "$GOOD_EN"; } > "$f"
check "persisted bootup under a path with a space: the file is read" "$f" allow "$EN"
PREVIEW_GONE="<persisted-output> Output too large (10.3KB). Full output saved to: $(native "$T")/gone.txt Preview (first 2KB): === BRAIN BOOTUP CHECK ==="
f="$T/22c.jsonl"; { boot_ok startup "$PREVIEW_GONE"; user "stand?"; asst "$GOOD_EN"; } > "$f"
check "persisted bootup whose file is gone: preview only, no block found (control)" "$f" block "$EN"

# 23 — any later turn: an item the list prints as ours is not moved to someone else in prose
# (measured 2026-10-26 on the Windows instance: an own PR, "[PR|ai] … still ours" at three
# starts, went under "open (with others)" at each close; the operator closed on that answer).
# A wait passes only as data: the instance's `waiting` map or a fresh open-items.py record.
CLOSE_BAD="Persisted.
- **Open (with others):**
  - example-market #61 waits for the reviewer's read.
You can shut down."
CLOSE_OURS="Persisted. Still ours: example-market #61 — I merge it next session. You can shut down."
f="$T/23a.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_EN"; user "and now?"; asst "$CLOSE_BAD"; } > "$f"
check "later turn: an ours item put under a with-others heading" "$f" block "$EN"
f="$T/23b.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_EN"; user "and now?"; asst "Only #61, it is waiting on the owner."; } > "$f"
check "later turn: an ours item said to wait, same line" "$f" block "$EN"
f="$T/23c.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_EN"; user "and now?"; asst "$CLOSE_OURS"; } > "$f"
check "later turn: the same item said as ours" "$f" allow "$EN"
f="$T/23d.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_EN"; user "and now?"; asst "#112 is waiting on its owner."; } > "$f"
check "later turn: a parked item said to wait (not ours, control)" "$f" allow "$EN"
WS="$T/cwd-seen"; mkdir -p "$WS/.claude-state"
printf '%s\n' '{"items":{"example-market#61":{"first":"2026-10-07","sessions":[],"wait":"waiting on someone: our review is in"}}}' > "$WS/.claude-state/open-items-seen.json"
f="$T/23e.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_EN"; user "and now?"; asst "$CLOSE_BAD"; } > "$f"
check "later turn: the wait on record in a fresh open-items run" "$f" allow "$WS"
WM="$T/cwd-wait"; mkdir -p "$WM/.claude/rules"
printf '%s\n' '{"waiting":{"example-market#61":{"until":"2099-01-01","why":"reviewer"}}}' > "$WM/.claude/rules/open-items.json"
check "later turn: the wait on record in the instance waiting map" "$f" allow "$WM"
WD="$T/cwd-wait-de"; mkdir -p "$WD/.claude/rules"
printf '%s\n' '{"wait_patterns":["\\bbei anderen\\b","\\bwartet auf\\b"]}' > "$WD/.claude/rules/open-items.json"
f="$T/23f.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_EN"; user "noch was offen?"; asst "Gesichert.
- **Offen (bei anderen):**
  - example-market #61: es fehlt nur noch die Durchsicht."; } > "$f"
check "later turn, German heading through instance data" "$f" block "$WD"
check "later turn, German heading without instance data (built-ins are English)" "$f" allow "$EN"
# 23w-z — the three false blocks measured on the Windows instance at 762da50 (agent-brain#120).
f="$T/23w.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_EN"; user "and now?"; asst "Open: the UI layout from 2026-09-05 waits for your decision."; } > "$f"
check "later turn: a human item relayed as waiting for the operator (not a relabel)" "$f" allow "$EN"
f="$T/23x.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_EN"; user "and now?"; asst "Still ours: #61 - waiting for CI to go green, then I merge it."; } > "$f"
check "later turn: an ours item waiting for CI, said as ours" "$f" allow "$EN"
f="$T/23y.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_EN"; user "and now?"; asst "Waiting on others:
  - a fixtures anfrage of their own, worlds 2D and 3D."; } > "$f"
check "later turn: topic words under a wait heading do not name an item (strict naming; the old matcher took two slug words)" "$f" allow "$EN"
f="$T/23z.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_EN"; user "and now?"; asst "Waiting on others:
  - core/anfrage-fixtures-2026-09-13.md, their review."; } > "$f"
check "later turn: the exact file under a wait heading still names the item" "$f" block "$EN"
# The close turn (session-closing.sh --pre-commit ran) and every "nothing open" must name what
# is still ours (measured 2026-10-25: a close said "all saved" and named none).
CLOSE_CMD='{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"bash core/helpers/session-closing.sh --pre-commit --session x"}}]}}'
GOOD_ALL="$GOOD_EN"
f="$T/23g.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_ALL"; user "close the session"; echo "$CLOSE_CMD"; asst "Persisted - you can shut down."; } > "$f"
check "close report naming none of the ours items" "$f" block "$EN"
f="$T/23h.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_ALL"; user "close the session"; echo "$CLOSE_CMD"; asst "Still ours: #61, the fixtures answer (09-13); for you: 09-05 UI layout, 09-08 bridge question. Persisted - you can shut down."; } > "$f"
check "close report naming every ours item" "$f" allow "$EN"
f="$T/23i.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_ALL"; user "anything left?"; asst "No, nothing is open."; } > "$f"
check "a later 'nothing open' while ours items stand" "$f" block "$EN"
WG="$T/cwd-gone"; mkdir -p "$WG/.claude-state"
printf '%s\n' '{"items":{"widget-suite/anfrage-ui-2026-09-05.md":{"first":"2026-10-01","sessions":[]},"demo-area/anfrage-bridge-2026-09-08.md":{"first":"2026-10-01","sessions":[]},"core/anfrage-fixtures-2026-09-13.md":{"first":"2026-10-01","sessions":[]}}}' > "$WG/.claude-state/open-items-seen.json"
f="$T/23j.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_ALL"; user "and now?"; asst "Persisted.
- **Open (with others):**
  - #61 merged, waiting for a tag."; } > "$f"
check "an item a later run no longer lists (merged) under a with-others heading" "$f" allow "$WG"
check "the same reply while the item still stands (control)" "$f" block "$EN"
# The operator asks whether anything is still open: the answer names what is ours (measured
# 2026-10-25: "surely all closed, final?" — "persisted, you can shut down", nothing named).
f="$T/23k.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_ALL"; user "anything still open?"; asst "Persisted - you can shut down."; } > "$f"
check "'anything still open?' answered without the ours items" "$f" block "$EN"
f="$T/23l.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_ALL"; user "anything still open?"; asst "Still ours: #61 and the fixtures answer (09-13); for you: 09-05 UI layout, 09-08 bridge question."; } > "$f"
check "'anything still open?' answered with every ours item" "$f" allow "$EN"
# The same question typed mid-turn is a queued_command attachment (turn-kind #139): it is the
# operator's word, so it counts as the ask; it opens no new turn, so the reply buffer stays.
qcmd() { printf '{"type":"attachment","attachment":{"type":"queued_command","prompt":%s,"origin":{"kind":"human"}}}\n' "$(js "$1")"; }
f="$T/23q.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_ALL"; user "fix the parser"; asst "working on it"; qcmd "anything still open?"; asst "Persisted - you can shut down."; } > "$f"
check "'anything still open?' typed mid-turn, answered without the ours items" "$f" block "$EN"
f="$T/23r.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_ALL"; user "fix the parser"; asst "working on it"; asst "Persisted - you can shut down."; } > "$f"
check "the same turn without the mid-turn question (control)" "$f" allow "$EN"
f="$T/23m.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_ALL"; user "sicher alles abgeschlossen final?"; asst "Persistiert, du kannst herunterfahren."; } > "$f"
printf '%s\n' '{"ask_patterns":["\\balles\\b[^?\\n]{0,30}\\babgeschlossen\\b"]}' > "$WD/.claude/rules/open-items.json"
check "German ask through instance data" "$f" block "$WD"
check "German ask without instance data (control)" "$f" allow "$EN"

# 24 — the close report and its open ends (measured 2026-10-28 on a session transcript): the close
# listed an own item as an `open end:` line of its session-log entry (close-stamp.cjs, skill
# session-close step 4) and the gate still blocked the close report for it. An item named in an
# open-end line of THIS close, or carrying a wait record, is not missing; the reason names the
# close report, and the stop-checks template turns it into a line that says so.
CLOSE_PART="Still ours: #61; for you: 09-05 TD split, 09-08 bridge question. Persisted - you can shut down."
f="$T/24.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_ALL"; user "close the session"; echo "$CLOSE_CMD"; asst "$CLOSE_PART"; } > "$f"
check "close report leaving out an item, no open-end line" "$f" block "$EN"
LOGHEAD="- 2026-10-28 session x: close"
OE="$T/cwd-openend"; mkdir -p "$OE/.claude-state" "$OE/docs/maintenance"
printf '%s\n%s\n' "x" "$LOGHEAD" > "$OE/.claude-state/session-close.stamp"
printf '%s\n%s\n%s\n' "$LOGHEAD" "  - open end: core/anfrage-fixtures-2026-09-13.md — peer-d answers" "- next entry" > "$OE/docs/maintenance/session-log.md"
check "the same item named in an open-end line of this close" "$f" allow "$OE"
OO="$T/cwd-openend-other"; mkdir -p "$OO/.claude-state" "$OO/docs/maintenance"
printf '%s\n%s\n' "x" "$LOGHEAD" > "$OO/.claude-state/session-close.stamp"
printf '%s\n%s\n' "$LOGHEAD" "  - open end: arche/suite-y #7 — CI of the branch" > "$OO/docs/maintenance/session-log.md"
check "an open-end line naming another item (control)" "$f" block "$OO"
OS="$T/cwd-openend-stale"; mkdir -p "$OS/docs/maintenance"
printf '%s\n%s\n' "$LOGHEAD" "  - open end: core/anfrage-fixtures-2026-09-13.md — peer-d answers" > "$OS/docs/maintenance/session-log.md"
check "an open-end line without this close's stamp (control)" "$f" block "$OS"
f2="$T/24b.jsonl"; { boot_ok startup "$BLOCK"; user "stand?"; asst "$GOOD_ALL"; user "anything still open?"; asst "$CLOSE_PART"; } > "$f2"
check "open-end lines count only in the close turn (control)" "$f2" block "$OE"
WR="$T/cwd-close-wait"; mkdir -p "$WR/.claude/rules"
printf '%s\n' '{"waiting":{"core/anfrage-fixtures-2026-09-13.md":{"until":"2099-01-01","why":"peer-d answers"}}}' > "$WR/.claude/rules/open-items.json"
check "the same item carrying a wait record" "$f" allow "$WR"
out24="$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$(native "$f")" "$(native "$EN")" | node "$G" 2>&1)"
line24="$(printf '%s' "$out24" | node -e '
const fs = require("fs");
const tpl = JSON.parse(fs.readFileSync(process.argv[1], "utf8")).checks.find((c) => c.marker === "OPEN-ITEMS-GATE");
const reason = JSON.parse(fs.readFileSync(0, "utf8")).reason;
const m = new RegExp(tpl.extract).exec(reason);
process.stdout.write(m ? tpl.template.replace("{1}", m[1]).replace("{2}", m[2]) : "NO MATCH");
' "$(native "$D/../templates/rules-instance/stop-checks.json")" 2>&1)"
case "$line24" in
  "The close report"*"anfrage-fixtures-2026-09-13.md"*) ok "the stop-check line names the close report and the item" ;;
  *) bad "the stop-check line does not name the close report: '$line24'" ;;
esac
case "$line24" in *[Ff]"irst reply"*) bad "the close-report line says first reply: '$line24'" ;; *) ok "the close-report line does not say first reply" ;; esac

[ "$fail" = 0 ] && echo "open-items-gate: all cases pass" || { echo "open-items-gate: FAILURES"; exit 1; }
