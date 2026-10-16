#!/usr/bin/env bash
# covers: watch-gate close-stamp
# Fixture test for helpers/watch-gate.cjs — both directions.
# The must-block case is the incident itself (2026-10-09): an answer pushed into the
# shared-memory repo, addressed to another instance, turn ended, no watcher — the
# follow-up request only surfaced when the operator asked. Must-allow cases carry the
# weight: a live watcher (plain or inside collab-watch), a closed entry (`status: info`),
# a note to oneself, someone else's entry, a push in an EARLIER turn, a re-issue. A dead
# pid in the lock (an expired Monitor) must count as not armed. CI side (2026-10-13): a push
# into a checkout with workflows, a PR or a merge naming a repo, each without a ci-watch on
# that repo in the turn, must block; a push into a repo without workflows must not. Hand step
# (2026-10-11): a request to the human in the reply without a waiter in the turn must block; a
# Monitor or background waiter, a visible "⚙ no watcher:" line, past tense and a quoted request
# must not. GitHub side: a ticket or a question in a thread without a repo watch must block.
# Usage: bash scripts/test-watch-gate.sh (exit 0 = pass)
set -u
T="$(mktemp -d)"
SLEEPERS=()
trap 'for p in "${SLEEPERS[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$T"' EXIT
G="$(cd "$(dirname "$0")" && pwd)/../helpers/watch-gate.cjs"
# Offline: a fake gh answers "does the named repo have workflows?" — o/plain has none (404),
# o/down cannot be measured (network error), every other repo has one.
# A node script, not a shell script: the gate runs it through node, which works on every OS
# (Windows node cannot exec a shebang file — OS-3, "a fixture hands a shell script to a native process").
printf '%s\n' 'const a = process.argv.slice(2).join(" ");' \
  'if (a.includes("repos/o/plain/")) { process.stderr.write("gh: Not Found (HTTP 404)\n"); process.exit(1); }' \
  'if (a.includes("repos/o/down/")) { process.stderr.write("error connecting to api.github.com\n"); process.exit(1); }' \
  'process.stdout.write("1\n");' > "$T/fake-gh.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
[ -f "$G" ] || { echo "  FAIL gate missing: $G"; exit 1; }

# OS-3: node opens these paths; a Git-Bash /tmp path would not resolve on Windows.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
export WATCH_GATE_GH="$(native "$T/fake-gh.cjs")"
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }

SM="$T/brain-shared-memory"
fresh() { # a new history, so exactly the next entry is in range
  rm -rf "$SM"; git init -q "$SM"; mkdir -p "$SM/core"
  git -C "$SM" config user.email t@t; git -C "$SM" config user.name t; git -C "$SM" config core.autocrlf false
}
fresh
entry() { # $1 file, $2 von, $3 audience, [$4 status]
  { echo '---'; echo "name: x"; echo 'metadata:'; echo "  von: $2"; echo "  audience: $3"
    [ -n "${4:-}" ] && echo "  status: $4"; echo '---'; echo body; } > "$SM/core/$1"
  git -C "$SM" add -A; git -C "$SM" commit -q -m "$1"
}

user() { printf '{"timestamp":"%s","message":{"role":"user","content":%s}}\n' "${2:-2020-01-01T00:00:00Z}" "$(js "$1")"; }
tool() { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"%s","input":{"command":%s%s}}]}}\n' \
  "$1" "$(js "$2")" "${3:+,\"run_in_background\":true}"; }
asst() { printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(js "$1")"; }
PUSH="cd ~/Projects/brain-shared-memory && git commit -q -m x && git push -q"

check() { # $1 name, $2 transcript, $3 block|allow, $4 project root, [$5 stop_hook_active]; $SID = session id
  local out
  out="$(printf '{"transcript_path":"%s","stop_hook_active":%s,"session_id":"%s"}' "$(native "$2")" "${5:-false}" "${SID:-}" \
    | CLAUDE_PROJECT_DIR="$(native "$4")" SHARED_MEMORY_REPO="$(native "$SM")" SHARED_MEMORY_SELF="ws" \
      node "$G" 2>&1)"
  if [ "$3" = block ]; then
    case "$out" in *'"decision":"block"'*) ok "$1 blocks";; *) bad "$1 did not block: '$out'";; esac
  else
    [ -z "$out" ] && ok "$1 allows" || bad "$1 blocked wrongly: '$out'"
  fi
}
live_lock() { sleep 60 & SLEEPERS+=("$!"); mkdir -p "$(dirname "$1")"; echo "$!" > "$1"; }

R="$T/brain"; mkdir -p "$R"

# --- the incident: answer to another party pushed, no watcher
entry answer.md ws mac
{ user "bitte windows checks starten"; tool Bash "$PUSH"; asst "done"; } > "$T/t1.jsonl"
check "pushed answer to another party, no watcher" "$T/t1.jsonl" block "$R"

# notifications inside the turn are not a boundary
{ user "go"; tool Bash "$PUSH"; user "<task-notification>agent done</task-notification>"; asst "ok"; } > "$T/t2.jsonl"
check "push, then a task notification" "$T/t2.jsonl" block "$R"

# an expired Monitor leaves a dead pid
mkdir -p "$R/.claude-state"; echo 999999 > "$R/.claude-state/shared-memory-watch.pid"
check "lock with a dead pid (expired watch)" "$T/t1.jsonl" block "$R"

# --- must allow
live_lock "$R/.claude-state/shared-memory-watch.pid"
check "live shared-memory watcher" "$T/t1.jsonl" allow "$R"
rm -f "$R/.claude-state/shared-memory-watch.pid"
live_lock "$R/.claude-state/collab-watch/shared-memory-watch.pid"
check "live watcher inside collab-watch" "$T/t1.jsonl" allow "$R"
rm -rf "$R/.claude-state"

check "re-issue (stop_hook_active)" "$T/t1.jsonl" allow "$R" true
{ cat "$T/t1.jsonl"; user "Stop hook feedback: WATCH-GATE: ..."; asst "nothing awaited: pure log line"; } > "$T/t3.jsonl"
check "second stop in the same turn" "$T/t3.jsonl" allow "$R"
{ cat "$T/t1.jsonl"; user "next question" "2099-01-01T00:00:00Z"; asst "answer"; } > "$T/t4.jsonl"
check "push was in an earlier turn" "$T/t4.jsonl" allow "$R"
{ user "go"; tool Bash "cd ~/Projects/other && git push -q"; } > "$T/t5.jsonl"
check "push to another repo" "$T/t5.jsonl" allow "$R"

fresh; entry info.md ws mac info
check "entry closed with status: info" "$T/t1.jsonl" allow "$R"
fresh; entry self.md ws ws
check "note addressed to this instance only" "$T/t1.jsonl" allow "$R"
fresh; entry foreign.md mac ws
check "entry pulled in from another instance" "$T/t1.jsonl" allow "$R"

# --- LOG.md messages (2026-10-16: a request and its answer, both LOG headings, were invisible)
logentry() { # $1 heading after the date, e.g. "ws — AN mac: please check"
  mkdir -p "$SM/ops"; printf '## 2026-10-16 · %s\nbody\n\n' "$1" >> "$SM/ops/LOG.md"
  git -C "$SM" add -A; git -C "$SM" commit -q -m log
}
fresh; logentry "ws — AN mac: please run the fixture"
check "LOG request to another party, no watcher" "$T/t1.jsonl" block "$R"
fresh; logentry "ws (second session) — AN mac + win: please check"
check "LOG request, session-tagged sender, two addressees" "$T/t1.jsonl" block "$R"
fresh; logentry "ws — AN mac (status: open): fix needed"
check "LOG request with an open status" "$T/t1.jsonl" block "$R"
fresh; logentry "ws — AN mac (status: done): re fixture — 27/27"
check "LOG answer closed with status: done" "$T/t1.jsonl" allow "$R"
fresh; logentry "ws — AN ws: note to self"
check "LOG note addressed to this instance only" "$T/t1.jsonl" allow "$R"
fresh; logentry "mac — AN ws: please take over"
check "LOG entry from another instance" "$T/t1.jsonl" allow "$R"
fresh; logentry "ws — status line without an addressee"
check "LOG heading without AN is no message" "$T/t1.jsonl" allow "$R"
fresh; logentry "ws — AN mac: please run the fixture"
live_lock "$R/.claude-state/shared-memory-watch.pid"
check "LOG request with a live watcher" "$T/t1.jsonl" allow "$R"
rm -rf "$R/.claude-state"

# --- PR side
{ user "build the PR"; tool Bash "gh pr create --title x --body y"; asst "PR #1"; } > "$T/p1.jsonl"
check "PR created, no watch" "$T/p1.jsonl" block "$R"
{ user "build the PR"; tool Bash "gh pr create --title x --body y"; tool Monitor "bash core/scripts/watch-pr.sh o/r 1 60"; } > "$T/p2.jsonl"
check "PR created, watch-pr armed in the turn" "$T/p2.jsonl" allow "$R"
live_lock "$R/.claude-state/collab-watch/repo-activity-o.pid"
check "PR created, collab-watch repo watch lives" "$T/p1.jsonl" allow "$R"
rm -rf "$R/.claude-state"
# a collab-watch with its own COLLAB_WATCH_STATE (measured 2026-10-15, Windows instance): the
# variable lives on the Monitor command, so the gate finds the dir only through the registry
OWN="$T/own-state"
live_lock "$OWN/repo-activity-o.pid"
check "PR created, own-state collab-watch not registered" "$T/p1.jsonl" block "$R"
mkdir -p "$R/.claude-state"; (cygpath -m "$OWN" 2>/dev/null || echo "$OWN") > "$R/.claude-state/collab-watch-states"  # Windows form, as collab-watch.sh writes it
check "PR created, own-state collab-watch registered" "$T/p1.jsonl" allow "$R"
live_lock "$OWN/shared-memory-watch.pid"
check "pushed answer, own-state collab-watch registered" "$T/t1.jsonl" allow "$R"
rm -rf "$R/.claude-state" "$OWN"

# --- CI side (measured 2026-10-13): a push into a checkout with Actions workflows starts a run.
# Four of five such pushes that session had a ci-watch; the fifth went red and nobody saw it.
CI="$T/cirepo"; git init -q "$CI"; mkdir -p "$CI/.github/workflows"; echo "name: ci" > "$CI/.github/workflows/ci.yml"
git -C "$CI" remote add origin https://github.com/o/r.git
PLAIN="$T/plainrepo"; git init -q "$PLAIN"; git -C "$PLAIN" remote add origin https://github.com/o/plain.git
CIN="$(native "$CI")"; PLAINN="$(native "$PLAIN")"
{ user "fix"; tool Bash "git -C $CIN push -q origin x"; asst "pushed"; } > "$T/c1.jsonl"
check "push into a repo with CI, no ci-watch" "$T/c1.jsonl" block "$R"
{ user "fix"; tool Bash "git -C $CIN push -q origin x"; tool Bash "bash core/scripts/ci-watch.sh pr o/r 7" bg; } > "$T/c2.jsonl"
check "push, ci-watch pr armed in the background" "$T/c2.jsonl" allow "$R"
{ user "fix"; tool Bash "git -C $CIN push -q origin x"; tool Monitor "bash core/scripts/ci-watch.sh ref o/r main"; } > "$T/c3.jsonl"
check "push, ci-watch ref armed via Monitor" "$T/c3.jsonl" allow "$R"
{ user "fix"; tool Bash "git -C $CIN push -q origin x"; tool Bash "bash core/scripts/ci-watch.sh pr o/other 7" bg; } > "$T/c4.jsonl"
check "negative control: ci-watch on another repo" "$T/c4.jsonl" block "$R"
{ user "fix"; tool Bash "git -C $CIN push -q origin x"; tool Bash "bash core/scripts/ci-watch.sh pr o/r 7"; } > "$T/c5.jsonl"
check "negative control: a foreground ci-watch call is not a watch" "$T/c5.jsonl" block "$R"
{ user "fix"; tool Bash "git -C $PLAINN push -q origin x"; } > "$T/c6.jsonl"
check "push into a repo without workflows" "$T/c6.jsonl" allow "$R"
{ user "fix"; tool Bash "cd $CIN && git push -q"; } > "$T/c7.jsonl"
check "cd-form push into a repo with CI" "$T/c7.jsonl" block "$R"
live_lock "$R/.claude-state/collab-watch/repo-activity-o.pid"
check "a live collab-watch lock does not replace the CI watch of a push" "$T/c1.jsonl" block "$R"
rm -rf "$R/.claude-state"
{ user "merge"; tool Bash "gh pr merge 5 --repo o/r --squash"; } > "$T/m1.jsonl"
check "merge names a repo, nothing watches the base branch" "$T/m1.jsonl" block "$R"
{ user "merge"; tool Bash "gh pr merge 5 --repo o/r --squash"; tool Bash "bash core/scripts/ci-watch.sh ref o/r main" bg; } > "$T/m2.jsonl"
check "merge, ci-watch ref armed" "$T/m2.jsonl" allow "$R"
{ user "pr"; tool Bash "gh pr create --repo o/r --title x"; tool Monitor "bash core/scripts/watch-pr.sh o/r 1 60"; } > "$T/p3.jsonl"
check "PR created with the repo named, reaction watch but no CI watch" "$T/p3.jsonl" block "$R"
{ user "pr"; tool Bash "gh pr create --repo o/r --title x"; tool Bash "bash core/scripts/ci-watch.sh pr o/r 1" bg; } > "$T/p4.jsonl"
check "PR created, ci-watch armed (also a PR-side watch)" "$T/p4.jsonl" allow "$R"
# A named repo without workflows starts no run (measured 2026-10-16 on macOS and Windows: a
# merge into a private repo without CI blocked the turn end with every watcher alive).
{ user "merge"; tool Bash "gh pr merge 2 -R o/plain --merge"; } > "$T/m3.jsonl"
check "merge names a repo without workflows (API 404)" "$T/m3.jsonl" allow "$R"
{ user "merge"; tool Bash "gh pr merge 2 -R o/plain --merge"; } > "$T/m4.jsonl"
check "merge names a repo whose local checkout has no workflows" "$T/m4.jsonl" allow "$PLAIN"
{ user "merge"; tool Bash "gh pr merge 2 -R o/r --merge"; } > "$T/m5.jsonl"
check "negative control: local checkout of the named repo has workflows" "$T/m5.jsonl" block "$CI"
{ user "merge"; tool Bash "gh pr merge 2 -R o/down --merge"; } > "$T/m6.jsonl"
check "negative control: workflows not measurable counts as CI" "$T/m6.jsonl" block "$R"

# --- a reload asked of the human (class measured 2026-10-11: "/mcp reconnect" asked, no waiter armed, noticed only when the operator said so)
{ user "update the plugin"; tool Bash "claude plugin install x"; asst "Installed. Please run /mcp to reconnect."; } > "$T/r1.jsonl"
check "reload asked, no waiter" "$T/r1.jsonl" block "$R"
{ user "update the plugin"; tool Bash "bash core/scripts/wait-mcp-reconnect.sh ~/.x/mcp-boot.json 900" bg; asst "Please run /mcp to reconnect."; } > "$T/r2.jsonl"
check "reload asked, waiter armed in the turn" "$T/r2.jsonl" allow "$R"
{ user "what is the state?"; tool Bash "git status"; asst "Clean. Nothing to reload."; } > "$T/r3.jsonl"
check "no reload asked" "$T/r3.jsonl" allow "$R"
{ user "update the plugin"; tool Bash "claude plugin install x"; asst "Bitte /reload-plugins."; } > "$T/r4.jsonl"
check "reload-plugins asked, no waiter" "$T/r4.jsonl" block "$R"
# A local command is not a prompt (measured 2026-10-11): the operator's /mcp leaves three
# frame-only records; the waiter armed before them must stay in the turn.
CAVEAT='<local-command-caveat>The command below was run directly in Claude Code, not sent to you as a request.</local-command-caveat>'
CMD='<command-name>/mcp</command-name>
            <command-message>mcp</command-message>
            <command-args></command-args>'
OUT='<local-command-stdout>Reconnected to grandma3.</local-command-stdout>'
{ user "update the plugin"; tool Bash "bash core/scripts/wait-mcp-reconnect.sh ~/.x/mcp-boot.json 900" bg
  asst "Please run /mcp to reconnect."; user "$CAVEAT"; user "$CMD"; user "$OUT"
  asst "Back. A reconnect re-read the tool list."; } > "$T/r5.jsonl"
check "waiter, then the operator's /mcp echo, then the reply" "$T/r5.jsonl" allow "$R"
{ user "update the plugin"; tool Bash "claude plugin install x"; asst "Please run /mcp to reconnect."
  user "$CAVEAT"; user "$CMD"; user "$OUT"; asst "Please run /mcp to reconnect again."; } > "$T/r6.jsonl"
check "negative control: /mcp echo, reload asked, no waiter" "$T/r6.jsonl" block "$R"

# --- a hand step asked of the human (class 2026-10-11: "onPC must be running" asked, no watcher, the operator reported the start)
{ user "check the desk"; tool Bash "git status"; asst "Please start onPC and load the show; I check the engine afterwards."; } > "$T/h1.jsonl"
check "hand step asked, no waiter" "$T/h1.jsonl" block "$R"
{ user "check the desk"; tool Monitor "bash scripts/onpc-watch.sh"; asst "Please start onPC and load the show; the watch reports the engine."; } > "$T/h2.jsonl"
check "hand step asked, Monitor armed in the turn" "$T/h2.jsonl" allow "$R"
{ user "check the desk"; tool Bash "bash scripts/wait-link.sh sw-foh 900" bg; asst "Please plug in the uplink cable; the link watch reports when it is up."; } > "$T/h3.jsonl"
check "hand step asked, background waiter armed" "$T/h3.jsonl" allow "$R"
{ user "check the desk"; tool Bash "git status"; asst "Could you switch on the router? ⚙ no watcher: office network, no probe allowed from here."; } > "$T/h4.jsonl"
check "hand step asked, no-watcher line names why" "$T/h4.jsonl" allow "$R"
{ user "check the desk"; tool Bash "git status"; asst "onPC must be running for the next step."; } > "$T/h5.jsonl"
check "necessity form (onPC must be running), no waiter" "$T/h5.jsonl" block "$R"
{ user "check the desk"; tool Bash "git status"; asst "I started onPC through the launcher and the engine answers."; } > "$T/h6.jsonl"
check "no request, past tense" "$T/h6.jsonl" allow "$R"
{ user "check the desk"; tool Bash "git status"; asst 'The ledger quotes the old reply "please start onPC" as the incident.'; } > "$T/h7.jsonl"
check "request only quoted" "$T/h7.jsonl" allow "$R"
mkdir -p "$R/.claude/rules"; printf '{"hand_step_patterns":["\\\\bzzhandzz\\\\b"]}\n' > "$R/.claude/rules/watch-gate.json"
{ user "check the desk"; tool Bash "git status"; asst "zzhandzz the desk now."; } > "$T/h8.jsonl"
check "instance hand-step pattern extends the built-ins" "$T/h8.jsonl" block "$R"
rm -f "$R/.claude/rules/watch-gate.json"

# --- a ticket or a question posted on GitHub (class 2026-10-11: a ticket opened, covered only by a collab-watch that happened to run)
{ user "file it"; tool Bash "gh issue create -R o/r --title x --body 'the limit'"; asst "Ticket opened."; } > "$T/i1.jsonl"
check "issue created, no repo watch" "$T/i1.jsonl" block "$R"
{ user "ask"; tool Bash "gh pr comment 7 -R o/r --body 'Which head did you test, please?'"; asst "Asked."; } > "$T/i2.jsonl"
check "question posted as a comment, no repo watch" "$T/i2.jsonl" block "$R"
{ user "report"; tool Bash "gh pr comment 7 -R o/r --body 'macOS check at abc: 50 pass, 0 fail.'"; asst "Reported."; } > "$T/i3.jsonl"
check "a comment that only reports" "$T/i3.jsonl" allow "$R"
live_lock "$R/.claude-state/collab-watch/repo-activity-o.pid"
check "issue created, collab-watch repo watch lives" "$T/i1.jsonl" allow "$R"
rm -rf "$R/.claude-state"

# --- the close turn (coherence scan 2026-10-15, P1-2): skill session-close arms no watcher it
# will not be alive to read and lists each item as an open end instead. A close stamp of this
# session and turn passes exactly the listed items; a stamp without the listing, another
# session's stamp, a stamp older than the turn, or no stamp at all still block.
toolid() { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","id":"%s","name":"Bash","input":{"command":%s}}]}}\n' "$1" "$(js "$2")"; }
result() { printf '{"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"%s","content":%s}]}}\n' "$1" "$(js "$2")"; }
CLOSE_LINE="- 2026-10-15 10:00:00 | main | close"
stamp() { # $1 stamp session id, $2 open-end lines of this close's entry (may be empty)
  mkdir -p "$R/.claude-state" "$R/docs/maintenance"
  printf '%s\n%s\n' "$1" "$CLOSE_LINE" > "$R/.claude-state/session-close.stamp"
  { echo "- 2026-10-14 09:00:00 | main | close"; echo "  open end: o/tool-suite #9 listed by an OLDER entry"
    echo "$CLOSE_LINE"; echo "  topic: fixture close"; [ -n "$2" ] && printf '%s\n' "$2"
    echo "- 2026-10-16 08:00:00 | main | close"; echo "  open end: o/tool-suite #9 listed by a LATER entry"; } > "$R/docs/maintenance/session-log.md"
}
PRE="bash core/helpers/session-closing.sh --pre-commit --session S1"
{ user "close the session"; tool Bash "$PRE"; toolid tu1 "gh pr create --repo o/tool-suite --title x --body-file b.md"
  result tu1 "https://github.com/o/tool-suite/pull/9"; asst "Persisted - you can shut down."; } > "$T/cs1.jsonl"
SID=S1
stamp S1 "  open end: o/tool-suite #9 awaits CI and review"
check "close stamp + PR and CI listed as open ends" "$T/cs1.jsonl" allow "$R"
stamp S1 ""
check "close stamp without the listing (older/later entries do not count)" "$T/cs1.jsonl" block "$R"
stamp S1 "  open end: o/tool-suite #90 awaits CI"
check "close stamp listing another PR number (#90 is not #9)" "$T/cs1.jsonl" block "$R"
stamp S1 "  open end: o/other-suite #9 awaits CI"
check "close stamp listing the number in another repo" "$T/cs1.jsonl" block "$R"
stamp OTHER "  open end: o/tool-suite #9 awaits CI and review"
check "close stamp of another session" "$T/cs1.jsonl" block "$R"
stamp "" "  open end: o/tool-suite #9 awaits CI and review"
check "close stamp without a session id (older harness), close ran in this turn" "$T/cs1.jsonl" allow "$R"
rm -rf "$R/.claude-state"
check "no close stamp, entry listed anyway" "$T/cs1.jsonl" block "$R"
stamp S1 "  open end: o/tool-suite #9 awaits CI and review"
{ user "close the session"; toolid tu1 "gh pr create --repo o/tool-suite --title x"; result tu1 "https://github.com/o/tool-suite/pull/9"; asst "done"; } > "$T/cs2.jsonl"
check "close stamp, but this turn never ran the close" "$T/cs2.jsonl" block "$R"
{ user "close the session" "2099-01-01T00:00:00Z"; tool Bash "$PRE"; toolid tu1 "gh pr create --repo o/tool-suite --title x"
  result tu1 "https://github.com/o/tool-suite/pull/9"; asst "done"; } > "$T/cs3.jsonl"
check "close stamp written before the turn began" "$T/cs3.jsonl" block "$R"
{ user "close the session"; tool Bash "$PRE"; tool Bash "$PUSH"; asst "Persisted - you can shut down."; } > "$T/cs4.jsonl"
fresh; entry close-request.md ws mac
stamp S1 "  open end: close-request (shared memory) awaits the answer from mac"
check "close stamp + shared-memory request listed by its file name" "$T/cs4.jsonl" allow "$R"
stamp S1 "  open end: some other request"
check "close stamp, shared-memory request not listed" "$T/cs4.jsonl" block "$R"
{ user "close the session"; tool Bash "$PRE"; toolid tu1 "gh pr create --repo o/tool-suite --title x"; result tu1 "https://github.com/o/tool-suite/pull/9"
  asst "Persisted. Please start onPC tomorrow."; } > "$T/cs5.jsonl"
stamp S1 "  open end: o/tool-suite #9 awaits CI and review"
check "close stamp never covers a hand step asked of the human" "$T/cs5.jsonl" block "$R"
SID=""
rm -rf "$R/.claude-state" "$R/docs"

# Windows: the hook does not run in Git Bash (measured 2026-10-11) — its PATH holds Git\cmd,
# not Git\usr\bin, so a bare `ps` is ENOENT and every live watcher read as dead. The gate must
# find Git's ps.exe itself. Run it with exactly that PATH: node's dir + Git\cmd.
if command -v cygpath >/dev/null 2>&1 && [ -d "/c/Program Files/Git/cmd" ]; then
  NODE_DIR="$(dirname "$(command -v node)")"
  live_lock "$R/.claude-state/shared-memory-watch.pid"
  fresh; entry answer2.md ws mac
  out="$(printf '{"transcript_path":"%s","stop_hook_active":false}' "$(native "$T/t1.jsonl")" \
    | PATH="$NODE_DIR:/c/Program Files/Git/cmd" CLAUDE_PROJECT_DIR="$(native "$R")" SHARED_MEMORY_REPO="$(native "$SM")" \
      SHARED_MEMORY_SELF="ws" "$NODE_DIR/node" "$(native "$G")" 2>&1)"
  [ -z "$out" ] && ok "Windows hook PATH (no Git\\usr\\bin): a live watcher still counts" || bad "Windows hook PATH: live watcher read as dead: '$out'"
  rm -rf "$R/.claude-state"
fi

# negative control: an always-allow stub must fail every must-block case, or the
# block assertions above prove nothing
printf 'process.stdin.resume();process.stdin.on("end",()=>process.exit(0));
' > "$T/stub.cjs"
G0="$G"; G="$T/stub.cjs"; before=$fail; fail=0
for c in t1 t2 p1 r1 r4 c1 c7 m1 p3 h1 h5 i1 i2 cs2 cs5; do check "stub on $c" "$T/$c.jsonl" block "$R" >/dev/null; done
caught=$fail; G="$G0"; fail=$before
[ "$caught" = 1 ] && ok "always-allow stub fails the must-block cases" || bad "negative control: stub passed every must-block case"

[ "$fail" = 0 ] && echo "watch-gate: all checks passed" || echo "watch-gate: FAILURES"
exit "$fail"
