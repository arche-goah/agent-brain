#!/bin/bash
# Fixture for helpers/claim-write-gate.cjs.
# Cases: no claim -> pass; write into a peer's claim -> deny naming it; own deeper claim inside the peer's -> pass;
# peer gone -> pass; peer in another root -> pass; a file next to (not inside) the claim -> pass.
# Paths go to node as data, so they are stated natively (os-traps OS-3).
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$(native "$HERE/../helpers/claim-write-gate.cjs")"
T="$(native "$(mktemp -d)")"; fail=0
ok() { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
ROOT="$T/brain"; mkdir -p "$ROOT/.claude-state/session-areas" "$T/cfg/sessions"
export CLAUDE_CONFIG_DIR="$T/cfg" CLAUDE_PROJECT_DIR="$ROOT"
reg() { printf '{"pid":%s,"sessionId":"%s","cwd":"%s","name":"%s","status":"busy"}\n' "$1" "$2" "$3" "$4" > "$T/cfg/sessions/$2.json"; }
rec() { printf '{"id":"%s","areas":{},"claims":[%s],"told":[]}' "$1" "$2" > "$ROOT/.claude-state/session-areas/$1.json"; }
run() { printf '{"session_id":"me","tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "$ROOT" | node "$GATE"; }
S="$ROOT/docs/business/einkauf"
reg 100 me "$ROOT" brain-a; reg 200 peer "$ROOT" brain-b
export SESSION_AREAS_ALIVE=100,200
rec me ''; rec peer ''
[ -z "$(run "$S/list.md")" ] && ok "no claim: pass" || bad "no claim: pass"
rec peer "{\"path\":\"$S\",\"note\":\"shopping\"}"
out="$(run "$S/sub/list.md")"
[[ "$out" == *'"deny"'* && "$out" == *brain-b* ]] && ok "write into a peer's claim: deny naming it" || bad "peer claim: deny ($out)"
[ -z "$(run "$ROOT/docs/business/other.md")" ] && ok "file beside the claim: pass" || bad "beside claim: pass"
[ -z "$(run "$ROOT/docs/business/einkaufsliste.md")" ] && ok "name prefix is not inside (einkauf vs einkaufsliste): pass" || bad "prefix: pass"
rec me "{\"path\":\"$S/sub\",\"note\":\"handed to me\"}"
[ -z "$(run "$S/sub/list.md")" ] && ok "own deeper claim inside the peer's: pass" || bad "own deeper claim: pass"
rec me ''
export SESSION_AREAS_ALIVE=100
[ -z "$(run "$S/list.md")" ] && ok "peer process gone: pass" || bad "peer gone: pass"
export SESSION_AREAS_ALIVE=100,200
rec peer "{\"path\":\"$S\",\"note\":\"shopping\"}"
reg 200 peer "$T/other" brain-b; rm "$ROOT/.claude-state/session-areas/peer.json"  # its record lives in its own root
[ -z "$(run "$S/list.md")" ] && ok "peer in another root: pass" || bad "other root: pass"
rm -rf "$T"
[ "$fail" = 0 ] && echo "claim-write-gate: all pass" || { echo "claim-write-gate: FAILURES"; exit 1; }
