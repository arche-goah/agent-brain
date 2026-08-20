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

echo
[ "$fail" -eq 0 ] && echo "session-helper fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
