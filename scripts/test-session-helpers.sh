#!/usr/bin/env bash
# covers: junk-cleaner notify statusline framing-intake memory-sync
#
# Effect proof for the helpers that are not gates. They fail differently and worse: a
# gate that stops firing lets something through and eventually someone notices; a
# helper that stops working produces NOTHING, and nothing looks exactly like "there was
# nothing to do".
#
# Usage: bash scripts/test-session-helpers.sh   (exit 0 = all fixtures pass)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

# Two layouts, one fixture: inside a brain the helpers live under core/helpers, inside
# the core repo itself under helpers. A fixture that only knows one of them silently
# tests nothing in the other — so resolution is explicit, and a missing subject is
# SKIPPED loudly rather than passing quietly.
resolve() {
  for cand in "core/$1" "$1"; do
    [ -f "$cand" ] && { printf '%s' "$cand"; return 0; }
  done
  return 1
}
skip() { echo "  --  $1 (not in this layout)"; }


echo "session helpers:"

# --- junk-cleaner: removes what nobody wants, keeps what was written ---------
# The dangerous direction is the second one: a cleaner that deletes real work is worse
# than junk lying around, so both cases are asserted.
mkdir -p "$T/w"
touch "$T/w/.DS_Store" "$T/w/real.py"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s/w/real.py"},"cwd":"%s"}' "$T" "$ROOT" \
  | CLAUDE_PROJECT_DIR="$T" node "$(resolve helpers/junk-cleaner.cjs)" >/dev/null 2>&1
[ -f "$T/w/real.py" ] && ok "junk-cleaner keeps real files" || bad "junk-cleaner deleted real work"
# The contract this PR establishes: BOTH junk classes are removed from the project
# root — code-fragment filenames (size-capped) and OS/toolchain debris by exact name,
# including directories. Every other dotfile stays untouched; .env is the case that
# must never be collateral.
touch "$T/flex" "$T/.DS_Store" "$T/.env"
mkdir -p "$T/__pycache__" && touch "$T/__pycache__/x.pyc"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s/w/real.py"},"cwd":"%s"}' "$T" "$T" \
  | CLAUDE_PROJECT_DIR="$T" node "$(resolve helpers/junk-cleaner.cjs)" >/dev/null 2>&1
[ -f "$T/flex" ] && bad "junk-cleaner left a code-fragment file" \
  || ok "junk-cleaner removes code-fragment names"
[ -f "$T/.DS_Store" ] && bad "junk-cleaner left .DS_Store — the rule promises otherwise" \
  || ok "junk-cleaner removes .DS_Store"
[ -d "$T/__pycache__" ] && bad "junk-cleaner left __pycache__ — directories need their own path" \
  || ok "junk-cleaner removes __pycache__"
[ -f "$T/.env" ] && ok "junk-cleaner leaves other dotfiles alone" \
  || bad "junk-cleaner deleted .env — collateral damage"

# --- notify: must not crash on a payload, and must stay silent on stdout -----
# It talks to the OS notifier; the contract that matters for a hook is that it never
# writes to stdout (a hook's stdout is protocol) and never fails the turn.
out=$(printf '{"hook_event_name":"Notification","message":"fixture","cwd":"%s"}' "$ROOT" \
      | CLAUDE_PROJECT_DIR="$ROOT" node "$(resolve helpers/notify.cjs)" 2>/dev/null)
rc=$?
[ "$rc" -eq 0 ] && ok "notify exits clean" || bad "notify exited $rc"
[ -z "$out" ] && ok "notify keeps stdout free" || bad "notify wrote to stdout: $out"

# --- statusline: prints one line, and it is not empty ------------------------
out=$(printf '{"session_id":"fix","cwd":"%s","model":{"display_name":"test"}}' "$ROOT" \
      | CLAUDE_PROJECT_DIR="$ROOT" node "$(resolve helpers/statusline.cjs)" 2>/dev/null)
[ -n "$out" ] && ok "statusline produces output" || bad "statusline produced nothing"
[ "$(printf '%s' "$out" | wc -l | tr -d ' ')" -le 1 ] \
  && ok "statusline stays one line" || bad "statusline printed multiple lines"

# --- framing-intake: instance-only, so absence is a skip, not a failure ---------
FI=$(resolve scripts/hooks/framing-intake.sh || true)
if [ -n "$FI" ]; then
  out=$(CLAUDE_PROJECT_DIR="$ROOT" bash "$FI" 2>/dev/null)
  case "$out" in *"<reflexion"*) ok "framing-intake emits the reflexion block";;
                  *) bad "framing-intake produced no reflexion block";; esac
  case "$out" in *'instructions="never"'*) ok "framing-intake frames it as data";;
                  *) bad "framing-intake missing the data framing";; esac
else
  skip "framing-intake"
fi

# --- memory-sync: import/export round-trip without touching the real memory --
# Run against a throwaway root so the fixture can never damage actual memory.
mkdir -p "$T/m/docs/memory-snapshot"
printf '# Memory Index\n' > "$T/m/docs/memory-snapshot/MEMORY.md"
out=$(cd "$T/m" && CLAUDE_PROJECT_DIR="$T/m" node "$ROOT/$(cd "$ROOT" && resolve helpers/memory-sync.cjs)" export 2>&1)
rc=$?
[ "$rc" -eq 0 ] && ok "memory-sync export runs on a fresh root" \
  || bad "memory-sync export failed: ${out:0:100}"

# The manifest is tracked and the export runs as a Stop/SessionEnd hook: an export that
# changed nothing must not rewrite it (measured 2026-09-13: `lastSync` alone made the
# tree dirty after every close commit). Both directions — unchanged memory leaves the
# manifest byte-identical, a changed file changes it.
MS="$ROOT/$(cd "$ROOT" && resolve helpers/memory-sync.cjs)"
mkdir -p "$T/live"; printf 'one\n' > "$T/live/note.md"
manifest="$T/m/docs/memory-snapshot/.sync-manifest.json"
(cd "$T/m" && CLAUDE_PROJECT_DIR="$T/m" CLAUDE_MEMORY_DIR="$T/live" node "$MS" export >/dev/null 2>&1)
[ -f "$manifest" ] && ok "memory-sync export writes the manifest on first export" \
  || bad "memory-sync export wrote no manifest"
before=$(cat "$manifest" 2>/dev/null)
sleep 1   # lastSync is an ISO timestamp; an unchanged export must not depend on the second
(cd "$T/m" && CLAUDE_PROJECT_DIR="$T/m" CLAUDE_MEMORY_DIR="$T/live" node "$MS" export >/dev/null 2>&1)
[ "$(cat "$manifest")" = "$before" ] && ok "memory-sync export leaves the manifest untouched without a memory change" \
  || bad "memory-sync export rewrote the manifest although nothing changed"
printf 'two\n' > "$T/live/note.md"
(cd "$T/m" && CLAUDE_PROJECT_DIR="$T/m" CLAUDE_MEMORY_DIR="$T/live" node "$MS" export >/dev/null 2>&1)
[ "$(cat "$manifest")" != "$before" ] && ok "memory-sync export updates the manifest on a memory change" \
  || bad "memory-sync export missed a changed memory file"

# prune heals a manifest ghost: an entry whose file is gone from BOTH sides (memory
# deleted, snapshot copy removed by hand or by git) was never touched by prune, which
# only walked the snapshot files — memory-lint names it, so its fix must exist. The
# live entry beside it must survive (prune never drops a manifest line that still has
# a file).
node -e 'const f=process.argv[1],m=JSON.parse(require("fs").readFileSync(f,"utf8"));m.files["ghost.md"]={hash:"x",updated:"t"};require("fs").writeFileSync(f,JSON.stringify(m))' "$manifest"
(cd "$T/m" && CLAUDE_PROJECT_DIR="$T/m" CLAUDE_MEMORY_DIR="$T/live" node "$MS" prune >/dev/null 2>&1)
grep -q '"ghost.md"' "$manifest" && bad "memory-sync prune left a manifest entry without any file" \
  || ok "memory-sync prune drops a manifest entry without any file"
grep -q '"note.md"' "$manifest" && ok "memory-sync prune keeps a manifest entry that has its file" \
  || bad "memory-sync prune dropped a live entry"

# --- memory-sync: the base is per machine; a pulled snapshot is never overwritten -----
# Measured 2026-10-10: a machine whose memory had not synced for weeks pulled the other
# machine's snapshot mid-session; the Stop-hook export then read the TRACKED manifest (the
# other machine's view) as its base, saw every live file as "changed" and wrote the stale
# memory over the fresh snapshot. The base now lives in <live>/.sync-base.json. Three cases:
# no base yet (upgrade path), snapshot moved under an unchanged live, both sides moved.
ms_run() { (cd "$T/p" && CLAUDE_PROJECT_DIR="$T/p" CLAUDE_MEMORY_DIR="$T/plive" node "$MS" "$1" >/dev/null 2>&1); }
set_manifest_hash() { # as the other machine's export would have committed it
  node -e 'const fs=require("fs"),c=require("crypto");const [f,n,p]=process.argv.slice(1);
    let m={files:{}};try{m=JSON.parse(fs.readFileSync(f,"utf8"))}catch(e){}
    m.files[n]={hash:c.createHash("sha256").update(fs.readFileSync(p,"utf8")).digest("hex"),updated:"t"};
    fs.writeFileSync(f,JSON.stringify(m))' "$1" "$2" "$3"
}
mkdir -p "$T/p/docs/memory-snapshot" "$T/plive"
pman="$T/p/docs/memory-snapshot/.sync-manifest.json"
printf 'theirs\n' > "$T/p/docs/memory-snapshot/note.md"; set_manifest_hash "$pman" note.md "$T/p/docs/memory-snapshot/note.md"
printf 'mine, stale\n' > "$T/plive/note.md"
ms_run export
[ "$(cat "$T/p/docs/memory-snapshot/note.md")" = "theirs" ] && ok "memory-sync export without a base leaves a differing snapshot alone" \
  || bad "memory-sync export without a base overwrote the snapshot (the 2026-10-10 loss)"
ms_run import
[ -f "$T/plive/note.incoming.md" ] && ok "memory-sync import without a base keeps both sides (.incoming.md)" \
  || bad "memory-sync import without a base dropped one side"
rm -f "$T/plive/note.incoming.md"
# converge, so a base exists: both sides agree
printf 'theirs\n' > "$T/plive/note.md"; ms_run export
[ -f "$T/plive/.sync-base.json" ] && ok "memory-sync writes the per-machine base next to the live memory" \
  || bad "memory-sync wrote no .sync-base.json"
# the other machine moves the snapshot (a pull), live untouched
printf 'theirs v2\n' > "$T/p/docs/memory-snapshot/note.md"; set_manifest_hash "$pman" note.md "$T/p/docs/memory-snapshot/note.md"
ms_run export
[ "$(cat "$T/p/docs/memory-snapshot/note.md")" = "theirs v2" ] && ok "memory-sync export keeps a snapshot that moved under an unchanged live" \
  || bad "memory-sync export undid a pull"
ms_run import
[ "$(cat "$T/plive/note.md")" = "theirs v2" ] && [ ! -f "$T/plive/note.incoming.md" ] \
  && ok "memory-sync import takes the pulled snapshot into an unchanged live" \
  || bad "memory-sync import did not bring the pulled snapshot in cleanly"
# both sides move
printf 'mine v3\n' > "$T/plive/note.md"
printf 'theirs v3\n' > "$T/p/docs/memory-snapshot/note.md"; set_manifest_hash "$pman" note.md "$T/p/docs/memory-snapshot/note.md"
ms_run export
[ "$(cat "$T/p/docs/memory-snapshot/note.md")" = "theirs v3" ] && ok "memory-sync export holds a diverged file instead of overwriting" \
  || bad "memory-sync export overwrote a diverged snapshot"
ms_run import
[ "$(cat "$T/plive/note.md")" = "mine v3" ] && [ "$(cat "$T/plive/note.incoming.md" 2>/dev/null)" = "theirs v3" ] \
  && ok "memory-sync import keeps the local edit and parks the remote one as .incoming.md" \
  || bad "memory-sync import lost one side of a diverged file"

echo
[ "$fail" -eq 0 ] && echo "session-helper fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
