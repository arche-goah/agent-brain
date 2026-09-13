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

[ "$fail" -eq 0 ] && echo "test-onboarding-leak-check: all checks passed"
exit "$fail"
