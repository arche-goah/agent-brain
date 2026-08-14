#!/usr/bin/env bash
# Carrier for "core scripts must work OS-agnostically" (operator 2026-08-08).
#
# WHY EXECUTE INSTEAD OF LINT: the v1.2.0 regression (PR #27) was a BSD/GNU fallback
# that was written on macOS and never RUN on a GNU system — the comment next to it
# claimed "tries both forms", and that was exactly not true. A text pattern matches the
# description of a thing, not the thing itself (D-3). This script runs in CI on ubuntu,
# macos and windows (Git Bash, shell: bash) and executes the real scripts against a
# fixture instance. Divergent constructs (stat -c/-f, date -r) are thereby actually
# exercised on every OS, because the fixture activates every branch.
#
# Local: bash scripts/portability-smoke.sh   (exit 0 = all checks passed)
set -u
CORE="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T" "$CORE/.claude-state"' EXIT
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

# Fixture instance: a scan report (activates the mtime branch) + a failed scheduled run
# (activates the awk/read branch of the failure channel).
mkdir -p "$T/docs/research/brain-scan" "$T/docs/maintenance"
printf -- '- [P1] fixture-finding\n' > "$T/docs/research/brain-scan/scan-fixture.md"
printf '%s\t%s\tsmoke-fixture\tfail\tnote\n' "$(date +%s)" "$(date '+%F %T')" \
  > "$T/docs/maintenance/scheduled-runs.tsv"

# 1) session-bootup: must run through to END on every OS AND compute the report age.
#    The v1.2.0 breakage ended exactly here: aborted mid-body, output silently cut off.
out="$(CLAUDE_PROJECT_DIR="$T" bash "$CORE/helpers/session-bootup.sh" 2>&1)" || true
case "$out" in *"=== END BOOTUP ==="*) ok "bootup runs through to END";; *) bad "bootup aborts: $(printf '%s' "$out" | tail -3)";; esac
case "$out" in *"latest report 0d ago"*) ok "bootup computes report age (stat branch)";; *) bad "report age missing/wrong";; esac
case "$out" in *"scheduled run FAILED: smoke-fixture"*) ok "bootup failure channel";; *) bad "failure channel silent";; esac
case "$out" in *"aborted early"*) bad "bootup itself reports an abort";; *) ok "no abort marker";; esac

# 2) brain-scan freshness gate: a fresh report -> exit 0, WITHOUT starting a run
#    (CLAUDE_BIN points at true; if run.log appeared, the gate would be broken).
BRAIN_DIR="$T" CLAUDE_BIN="$(command -v true)" bash "$CORE/scripts/brain-scan.sh"; rc=$?
if [ "$rc" -eq 0 ] && [ ! -f "$T/docs/research/brain-scan/run.log" ]; then
  ok "scan-gate: fresh => exit 0, no run"
else
  bad "scan-gate: rc=$rc run.log=$([ -f "$T/docs/research/brain-scan/run.log" ] && echo created || echo missing)"
fi

# 3) run-record: one ok line and one fail line land as TSV columns in the instance.
BRAIN_DIR="$T" sh "$CORE/helpers/run-record.sh" smoke2 ok "note a"
BRAIN_DIR="$T" sh "$CORE/helpers/run-record.sh" smoke2 fail "note b"
n=$(awk -F'\t' '$3=="smoke2" && ($4=="ok" || $4=="fail")' "$T/docs/maintenance/scheduled-runs.tsv" | wc -l | tr -d ' ')
[ "$n" = "2" ] && ok "run-record writes TSV" || bad "run-record: $n instead of 2 lines"

# 4) loop-watchdog with a deadline: arm/remaining/disarm format epochs as clock time.
#    On GNU, `date -r <epoch>` meant "read file <epoch>" — under set -e that already
#    killed arm.
wd="$(bash "$CORE/scripts/loop-watchdog.sh" arm smoke-loop 30 5 2>&1)"; rc=$?
case "$rc:$wd" in
  0:*"end "[0-2][0-9]:[0-5][0-9]*) ok "watchdog arm formats the deadline";;
  *) bad "watchdog arm: rc=$rc $wd";;
esac
wd="$(bash "$CORE/scripts/loop-watchdog.sh" remaining 2>&1)"; rc=$?
case "$rc:$wd" in
  0:*"REST "*) ok "watchdog remaining";;
  *) bad "watchdog remaining: rc=$rc $wd";;
esac
wd="$(bash "$CORE/scripts/loop-watchdog.sh" disarm 2>&1)"; rc=$?
case "$rc:$wd" in
  0:*"disarmed: 'smoke-loop' ran "[0-2][0-9]:[0-5][0-9]*) ok "watchdog disarm with time proof";;
  *) bad "watchdog disarm: rc=$rc $wd";;
esac

# 5) Generators write LF on EVERY OS. Python's text mode translates "\n" into the
#    platform separator — the same file ended up with CRLF on Windows and LF on macOS
#    (measured 2026-08-10: 12 CRLF in a freshly generated REGISTRY.md, 65 in an
#    ecosystem.json). Same class as the cp1252 finding from 2026-08-04: text mode
#    follows the platform, not the format. Executed instead of linted, because only the
#    real run shows what lands in the bytes.
mkdir -p "$T/skills/smoke-skill"
printf -- '---\nname: smoke-skill\ndescription: fixture for the line-ending check\n---\n\n# Smoke\n' \
  > "$T/skills/smoke-skill/SKILL.md"
if python3 "$CORE/scripts/regen-skill-registry.py" --skills "$T/skills" >/dev/null 2>&1 \
   && [ -f "$T/skills/REGISTRY.md" ]; then
  if od -c "$T/skills/REGISTRY.md" | grep -q '\\r'; then
    bad "registry generator writes CRLF (newline= missing)"
  else
    ok "registry generator writes LF"
  fi
else
  bad "registry generator did not run (python3 present? exit?)"
fi

# 6) bootstrap-brain REJECTS a target path that is too long, instead of dying mid-run.
#    Measured 2026-08-10 (Windows 11, git 2.43): without core.longpaths git aborts at
#    target+content > 260 with "Filename too long", with longpaths at a ~243-character
#    target path with "'$GIT_DIR' too big" — both used to surface only AFTER the first
#    write, with a message that pointed at SSH. The check only runs where the limit
#    exists; on macOS/Linux it is reported as skipped, not as green.
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    _long="$T/$(printf 'x%.0s' $(seq 1 210))"
    _out="$(bash "$CORE/scripts/bootstrap-brain.sh" "$_long" 2>&1)"; _rc=$?
    if [ "$_rc" -ne 0 ] && printf '%s' "$_out" | grep -qi "target path is"; then
      if [ -e "$_long" ]; then
        bad "bootstrap path check: rejected, but target already created (too late)"
      else
        ok "bootstrap rejects a too-long target path before writing"
      fi
    else
      bad "bootstrap path check: rc=$_rc, output: $(printf '%s' "$_out" | head -1)"
    fi
    ;;
  *) ok "bootstrap path check: skipped (path limit only exists on Windows)" ;;
esac

# 7) The repo linters must RUN on every OS, not just on the ubuntu lint job. The
#    english-only ratchet shipped with a posix-path bug that only Windows could see
#    (backslash comparison, 100 findings on a clean tree — PR #60); the ubuntu-only
#    lint job was structurally blind to it. Same class as every other check here:
#    execution on the OS is the only proof.
if python3 "$CORE/scripts/english-only.py" >/dev/null 2>&1; then
  ok "english-only ratchet runs clean on this OS"
else
  bad "english-only ratchet failed on this OS (path handling? baseline drift?)"
fi
if python3 "$CORE/scripts/suite-check.py" "$CORE" >/dev/null 2>&1; then
  ok "suite-check self-run clean on this OS"
else
  bad "suite-check self-run failed on this OS"
fi

# 8) MCP reconnect waiter: detects a changed boot stamp, and reports a stamp that never
#    changes as UNKNOWN rather than green. Its predecessor read `ps` output, which is
#    exactly what does not exist on Windows — so this one is executed here on all three.
printf '{"pid":1,"startedAt":"first"}' > "$T/mcp-boot.json"
( sleep 2; printf '{"pid":2,"startedAt":"second"}' > "$T/mcp-boot.json" ) &
_w="$(MCP_WAIT_POLL=1 bash "$CORE/scripts/wait-mcp-reconnect.sh" "$T/mcp-boot.json" 20 2>&1)"; _rc=$?
wait
case "$_rc:$_w" in
  0:*"RECONNECT DETECTED"*) ok "reconnect waiter detects a new boot stamp";;
  *) bad "reconnect waiter: rc=$_rc $(printf '%s' "$_w" | tr '\n' ' ')";;
esac
_w="$(MCP_WAIT_POLL=1 bash "$CORE/scripts/wait-mcp-reconnect.sh" "$T/mcp-boot.json" 2 2>&1)"; _rc=$?
case "$_rc:$_w" in
  2:*TIMEOUT*) ok "reconnect waiter reports an unchanged stamp as unknown (rc=2)";;
  *) bad "reconnect waiter timeout path: rc=$_rc (expected 2)";;
esac

echo
if [ "$fail" -eq 0 ]; then echo "portability-smoke: ALL checks passed"; else echo "portability-smoke: FAILURE (see FAIL lines)"; fi
exit "$fail"
