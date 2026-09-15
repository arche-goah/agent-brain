#!/usr/bin/env bash
# covers: onboarding-verify
# test-onboarding-leak-check.sh — check 8 of onboarding-verify.sh ("no FOREIGN home
# paths in the own brain") must stay loud for a real leak and silent for the brain's
# own paths. Both directions, on a throwaway brain, without touching the real one.
#
# WHY (measured 2026-09-13, first run of the verify on a second machine of one brain):
# check 8 was red with two hits, both of them the brain's own paths.
#   1. The machine's Windows user profile carries a SPACE. The extraction pattern
#      `[A-Za-z0-9._-]+` stops there, so the hit was the first name only, and the
#      after-the-fact filter compared it against the full name from `id -un` — it could
#      never match. The own home path read as a foreign leak on every single run.
#      Worse: one hit came out of the report the check itself had written one line
#      earlier. The check reported its own output.
#   2. A brain that runs on more than one machine carries the other machine's username
#      in its docs, device profiles and archived reports (twelve occurrences here).
#      That is the same brain on another computer, not a foreign home.
# A gate that is structurally red teaches people to walk past a red gate. That is the
# opposite of what it is for — hence both directions are fixed and both are proven here.
#
# The fixture drives the real script (BRAIN_DIR + --out into the temp dir) and reads
# only its line 8; the other checks describe the machine, not the fixture brain. That
# grep carries -a (OS-5): the line it extracts IS the verdict this fixture judges.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY="$ROOT/scripts/onboarding-verify.sh"
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

[ -f "$VERIFY" ] || { bad "onboarding-verify.sh not found"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BRAIN="$TMP/brain"
mkdir -p "$BRAIN/.claude/rules" "$BRAIN/docs/maintenance" "$BRAIN/core"
printf '{}\n' > "$BRAIN/.claude/settings.json"
printf '{\n  "names": [],\n  "instances": [],\n  "own_home_names": ["othermachine"]\n}\n' \
  > "$BRAIN/.claude/rules/leak-names.json"

me="$(id -un)"
# The synthetic home paths are ASSEMBLED, never written out: this file is scanned by
# leak-scan.py like every other, and a literal foreign home path in a fixture is the
# very thing the scanner is there to catch (same reason test-coherence-scan-files.sh
# writes its example path in Windows spelling).
U="Users"; H="home"
line8() { # $1 = label for the failure message
  BRAIN_DIR="$BRAIN" bash "$VERIFY" "$BRAIN" --out "$TMP/report-$1.txt" 2>/dev/null \
    | grep -aE '^(OK|FAIL)[[:space:]]+8 ' || echo "MISSING line 8 ($1)"
}

# ── 1. the brain's own paths are not a leak ────────────────────────────────
# The running machine's own home path — with whatever spaces its username has.
printf 'ssh key at C:/%s/%s/.ssh/id_ed25519 and /%s/%s/notes\n' "$U" "$me" "$H" "$me" \
  > "$BRAIN/docs/maintenance/own-paths.md"
# The OTHER machine of the same brain, declared in leak-names.json.
printf 'the first machine kept its checkout under /%s/othermachine/Projects\n' "$U" \
  > "$BRAIN/docs/maintenance/second-machine.md"
# An archived report of this check — its own output class.
printf 'Shell start — marker in /%s/somebodyelse/.bashrc\n' "$U" \
  > "$BRAIN/docs/maintenance/onboarding-report-oldmachine-2026-01-01.txt"

out="$(line8 own)"
case "$out" in
  OK*) ok "own home path, other own machine and an archived report are not a leak" ;;
  *)   bad "own paths read as a leak: $out" ;;
esac

# ── 2. a real foreign path is still loud ───────────────────────────────────
printf 'copied from a tutorial: /%s/stranger/Library/Application Support/x\n' "$U" \
  > "$BRAIN/docs/maintenance/foreign.md"
out="$(line8 foreign)"
case "$out" in
  FAIL*stranger*) ok "a foreign home path is reported, and named" ;;
  FAIL*)          bad "foreign path reported but not named: $out" ;;
  *)              bad "foreign home path NOT reported — the check would be blind: $out" ;;
esac

# ── 3. the strip is not a blanket pass for every name ──────────────────────
# "otherlonger" starts with the declared "otherma..."? No — a name that merely begins
# with a declared one must still count: the declaration is a whole name, not a prefix.
rm "$BRAIN/docs/maintenance/foreign.md"
printf 'a different person: /%s/otherperson/docs\n' "$U" > "$BRAIN/docs/maintenance/similar.md"
out="$(line8 similar)"
case "$out" in
  FAIL*otherperson*) ok "a name that only looks similar to a declared one is still a leak" ;;
  *)                 bad "a similar name slipped through the strip: $out" ;;
esac

# ── 4. the strip is a whole name, not a prefix ─────────────────────────────
# Review 2026-09-13: `s|/Users/$me||g` had no boundary, so a foreign user whose name
# STARTS with an own name lost its home path before extraction — main said FAIL, the
# branch said OK.
# The stand-in is the DECLARED "othermachine", not the running user's name. Built from
# $me this case could not pass on the very machine class the fix is for (measured
# 2026-09-15, Windows profile with a space): it asserts that "${me}ia" appears in the
# output, while the extraction charset `[A-Za-z0-9._-]+` has no space and can only ever
# return the first word. The FAIL fired correctly there — the assertion was unreachable,
# not the strip broken. A space-free own name tests the same property on every machine.
# The running user's name stays covered by 1 (silent) and the space/case side by 5.
rm "$BRAIN/docs/maintenance/similar.md"
printf 'a stranger with a longer name: /%s/othermachineia/Projects/y\n' "$U" > "$BRAIN/docs/maintenance/prefix.md"
out="$(line8 prefix)"
case "$out" in
  FAIL*othermachineia*) ok "a foreign name that starts with an own name is still a leak" ;;
  *)                    bad "prefix of an own name stripped a foreign home path: $out" ;;
esac
rm "$BRAIN/docs/maintenance/prefix.md"

# ── 5. declared names: spaces, case and dots ───────────────────────────────
printf '{\n  "names": [],\n  "instances": [],\n  "own_home_names": ["othermachine", "first last", "a.b"]\n}\n' \
  > "$BRAIN/.claude/rules/leak-names.json"
printf 'profile /%s/First Last/AppData and /%s/A.B/x\n' "$U" "$U" > "$BRAIN/docs/maintenance/declared.md"
out="$(line8 declared)"
case "$out" in
  OK*) ok "a declared name with a space and different case is stripped as one name" ;;
  *)   bad "declared name with space/case read as a leak: $out" ;;
esac
printf 'someone else: /%s/aXb/x\n' "$U" > "$BRAIN/docs/maintenance/dot.md"
out="$(line8 dot)"
case "$out" in
  FAIL*aXb*) ok "a dot in a declared name is a dot, not a wildcard" ;;
  *)         bad "a dot in a declared name matched another character: $out" ;;
esac

# ── 6. only what git TRACKS is scanned ─────────────────────────────────────
# Measured 2026-09-15 on the second Windows machine: the single own-path false positive
# left on that machine came out of a local state log — untracked and gitignored, so it
# can never reach a remote, and it carried the harness's scratchpad path in the Windows
# 8.3 SHORT form of the running profile. No strip built from `id -un` can know that
# spelling. Scanning only tracked files removes the class; the check keeps its reach over
# everything that can actually leave the machine. Both directions, because "scan less" is
# exactly the kind of fix that can go silent in the wrong direction.
if command -v git >/dev/null 2>&1; then
  RB="$TMP/repobrain"
  mkdir -p "$RB/.claude/rules" "$RB/docs/maintenance"
  printf '{}\n' > "$RB/.claude/settings.json"
  printf '{\n  "names": [],\n  "instances": [],\n  "own_home_names": []\n}\n' \
    > "$RB/.claude/rules/leak-names.json"
  git -C "$RB" init -q >/dev/null 2>&1
  rline8() {
    BRAIN_DIR="$RB" bash "$VERIFY" "$RB" --out "$TMP/report-$1.txt" 2>/dev/null \
      | grep -aE '^(OK|FAIL)[[:space:]]+8 ' || echo "MISSING line 8 ($1)"
  }
  # untracked: present in the working tree, invisible to the check
  printf 'local scratch note: /%s/strangerx/Projects/y\n' "$U" > "$RB/docs/maintenance/untracked.md"
  out="$(rline8 untracked)"
  case "$out" in
    OK*) ok "an untracked file is not scanned — it cannot reach a remote" ;;
    *)   bad "untracked file reported as a leak: $out" ;;
  esac
  # the SAME file, now tracked: loud, and named
  git -C "$RB" add docs/maintenance/untracked.md >/dev/null 2>&1
  out="$(rline8 tracked)"
  case "$out" in
    FAIL*strangerx*) ok "the same file tracked is reported, and named" ;;
    FAIL*)           bad "tracked leak reported but not named: $out" ;;
    *)               bad "a tracked foreign path was NOT reported — the check went blind: $out" ;;
  esac
else
  ok "git not available — tracked-only scan not exercised (skipped, not assumed)"
fi

[ "$fail" -eq 0 ] && echo "test-onboarding-leak-check: all checks passed"
exit "$fail"
