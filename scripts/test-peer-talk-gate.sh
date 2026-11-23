#!/usr/bin/env bash
# covers: peer-talk-gate session-areas
# Fixture for helpers/peer-talk-gate.cjs and the talked-peer part of helpers/session-areas.cjs.
# Must block: a live peer in the same root that got no SendMessage; a message to another pid's socket is no talk.
# Must pass: no peer, the re-issue, a peer messaged by name (with ref) or by its socket, a talk early in a long
# transcript, a peer in another root, a peer whose process is gone, the same peer again within the cooldown.
# Overlaps: before the talk a shared folder is an overlap, after the talk it is not, a write INTO a claim still is.
# Usage: bash scripts/test-peer-talk-gate.sh   (exit 0 = pass)
set -u
_D="$(cd "$(dirname "$0")" && pwd)"
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
GATE="$(native "$_D/../helpers/peer-talk-gate.cjs")"
SA="$(native "$_D/../helpers/session-areas.cjs")"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
ROOT="$(native "$T/brain")"; mkdir -p "$T/brain/.claude-state/session-areas" "$T/cfg/sessions"
export CLAUDE_CONFIG_DIR="$(native "$T/cfg")" CLAUDE_PROJECT_DIR="$ROOT" SESSION_AREAS_NOW=2026-11-09T12:00:00.000Z
reg() { printf '{"pid":%s,"sessionId":"%s","cwd":"%s","name":"%s","status":"busy"}\n' "$1" "$2" "$3" "$4" > "$T/cfg/sessions/$2.json"; }
tr_send() { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"SendMessage","input":{"to":"%s","message":"x"}}]}}\n' "$1"; }
fresh() { rm -f "$T/brain/.claude-state/peer-talk-gate-last.json"; }
run() { # $1 transcript, $2 stop_hook_active
  printf '{"session_id":"me","transcript_path":"%s","stop_hook_active":%s,"cwd":"%s"}' "$(native "$1")" "${2:-false}" "$ROOT" | node "$GATE"
}
reg 100 me "$ROOT" brain-a
export SESSION_AREAS_ALIVE=100,200
: > "$T/empty.jsonl"
[ -z "$(run "$T/empty.jsonl")" ] && ok "no peer: pass" || bad "no peer: pass"
reg 200 peer "$ROOT" brain-b
fresh; out="$(run "$T/empty.jsonl")"
[[ "$out" == *'"decision":"block"'* && "$out" == *brain-b* ]] && ok "silent peer: block naming it" || bad "silent peer: block ($out)"
[[ "$out" == *"session-areas.cjs claim"* ]] && ok "the block names the claim command" || bad "claim command missing"
[ -z "$(run "$T/empty.jsonl" true)" ] && ok "re-issue after the block: pass" || bad "re-issue: pass"
[ -z "$(run "$T/empty.jsonl")" ] && ok "the same peer within the cooldown: pass" || bad "cooldown: pass"
[[ "$(SESSION_AREAS_NOW=2026-11-09T12:31:00.000Z run "$T/empty.jsonl")" == *'"decision":"block"'* ]] && ok "after the cooldown the peer holds again" || bad "after cooldown: block"
grep -q '"decision":"pass-cooldown"' "$T/brain/.claude-state/peer-talk-gate.jsonl" && ok "a cooldown pass is recorded" || bad "cooldown not recorded"
tr_send "brain-b [abc123]" > "$T/talked.jsonl"
fresh; [ -z "$(run "$T/talked.jsonl")" ] && ok "peer messaged (with ref): pass" || bad "peer messaged: pass"
tr_send "uds:/tmp/cc-socks/200.sock" > "$T/replied.jsonl"
fresh; [ -z "$(run "$T/replied.jsonl")" ] && ok "reply to the peer's socket address: pass" || bad "reply by socket: pass"
# Windows (measured 2026-11-23): the reply address is a named pipe from the registry's messagingSocketPath, no pid in it
printf '{"pid":200,"sessionId":"peer","cwd":"%s","name":"brain-b","status":"busy","messagingSocketPath":"\\\\\\\\.\\\\pipe\\\\LOCAL\\\\cc-msg-abc123"}\n' "$ROOT" > "$T/cfg/sessions/peer.json"
printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"SendMessage","input":{"to":"uds:\\\\\\\\.\\\\pipe\\\\LOCAL\\\\cc-msg-abc123","message":"x"}}]}}\n' > "$T/pipe.jsonl"
fresh; [ -z "$(run "$T/pipe.jsonl")" ] && ok "reply to the peer's Windows pipe address: pass" || bad "reply by pipe: pass"
printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"SendMessage","input":{"to":"uds:\\\\\\\\.\\\\pipe\\\\LOCAL\\\\cc-msg-zzz999","message":"x"}}]}}\n' > "$T/other-pipe.jsonl"
fresh; [[ "$(run "$T/other-pipe.jsonl")" == *'"decision":"block"'* ]] && ok "a message to another pipe: still block (control)" || bad "other pipe: block"
# Windows (measured 2026-11-23): the reply address is a named pipe, read from the registry's messagingSocketPath
printf '{"pid":200,"sessionId":"peer","cwd":"%s","name":"brain-b","status":"busy","messagingSocketPath":"\\\\\\\\.\\\\pipe\\\\LOCAL\\\\cc-msg-ab12"}\n' "$ROOT" > "$T/cfg/sessions/peer.json"
node -e 'console.log(JSON.stringify({message:{role:"assistant",content:[{type:"tool_use",name:"SendMessage",input:{to:"uds:\\\\.\\pipe\\LOCAL\\cc-msg-ab12",message:"x"}}]}}))' > "$T/pipe.jsonl"
fresh; [ -z "$(run "$T/pipe.jsonl")" ] && ok "reply to the peer's named-pipe address (registry): pass" || bad "reply by named pipe: pass"
node -e 'console.log(JSON.stringify({message:{role:"assistant",content:[{type:"tool_use",name:"SendMessage",input:{to:"uds://./pipe/LOCAL/cc-msg-ab12",message:"x"}}]}}))' > "$T/pipe-fwd.jsonl"
fresh; [ -z "$(run "$T/pipe-fwd.jsonl")" ] && ok "the same pipe in forward-slash form: pass" || bad "pipe in forward-slash form: pass"
node -e 'console.log(JSON.stringify({message:{role:"assistant",content:[{type:"tool_use",name:"SendMessage",input:{to:"uds:\\\\.\\pipe\\LOCAL\\cc-msg-ff99",message:"x"}}]}}))' > "$T/pipe2.jsonl"
fresh; [[ "$(run "$T/pipe2.jsonl")" == *'"decision":"block"'* ]] && ok "another session's named pipe: still block (control)" || bad "other pipe: block"
reg 200 peer "$ROOT" brain-b
tr_send "uds:/tmp/cc-socks/2000.sock" > "$T/other-sock.jsonl"
fresh; [[ "$(run "$T/other-sock.jsonl")" == *'"decision":"block"'* ]] && ok "a message to another pid's socket: still block (control)" || bad "other socket: block"
{ tr_send "brain-b"; node -e 'const l=JSON.stringify({message:{role:"assistant",content:[{type:"text",text:"x".repeat(1000)}]}}); for (let i=0;i<5200;i++) console.log(l)'; } > "$T/long.jsonl"
fresh; [ -z "$(run "$T/long.jsonl")" ] && ok "talk early in a transcript over 5 MB still counts" || bad "early talk in long transcript"
reg 200 peer "$(native "$T/other")" brain-b
fresh; [ -z "$(run "$T/empty.jsonl")" ] && ok "peer in another root: pass" || bad "peer in another root: pass"
reg 200 peer "$ROOT" brain-b
fresh; [ -z "$(SESSION_AREAS_ALIVE=100 run "$T/empty.jsonl")" ] && ok "peer process gone: pass" || bad "peer gone: pass"
# overlaps: both write docs/maintenance; peer claims docs/maintenance/carrier.md, I claim docs/maintenance/ledger.md
NOW=$SESSION_AREAS_NOW
D="$ROOT/docs/maintenance"
printf '{"id":"me","areas":{"%s":{"at":"%s","root":"%s"}},"claims":[{"path":"%s/ledger.md","note":"a"}],"told":[]}' "$D" "$NOW" "$ROOT" "$D" > "$T/brain/.claude-state/session-areas/me.json"
printf '{"id":"peer","areas":{"%s":{"at":"%s","root":"%s"}},"claims":[{"path":"%s/carrier.md","note":"b"}],"told":[]}' "$D" "$NOW" "$ROOT" "$D" > "$T/brain/.claude-state/session-areas/peer.json"
cnt() { node -e '
  const sa = require(process.argv[1]); const now = Date.parse(process.argv[2]);
  const all = sa.sessions(process.argv[3], now); const me = all.find((s) => s.id === "me");
  const talked = process.argv[4] ? sa.talkedTo(process.argv[4]) : undefined;
  process.stdout.write(String(sa.overlaps(me, all.filter((s) => s.id !== "me"), now, talked).length));' "$SA" "$NOW" "$ROOT" "$1"; }
[ "$(cnt "")" -gt 0 ] && ok "before the talk: shared folder is an overlap (control)" || bad "before the talk: overlap expected"
[ "$(cnt "$(native "$T/talked.jsonl")")" = 0 ] && ok "after the talk: folder-level overlap settled" || bad "after the talk: expected 0, got $(cnt "$(native "$T/talked.jsonl")")"
printf '{"id":"peer","areas":{"%s/carrier.md":{"at":"%s","root":"%s"}},"claims":[],"told":[]}' "$D" "$NOW" "$ROOT" > "$T/brain/.claude-state/session-areas/peer.json"
printf '{"id":"me","areas":{},"claims":[{"path":"%s","note":"all of maintenance"}],"told":[]}' "$D" > "$T/brain/.claude-state/session-areas/me.json"
[ "$(cnt "$(native "$T/talked.jsonl")")" -gt 0 ] && ok "after the talk: a write INTO my claimed folder still is an overlap" || bad "write into claim after talk"
[ "$fail" = 0 ] && echo "test-peer-talk-gate: all checks passed" || { echo "test-peer-talk-gate: FAILED"; exit 1; }
