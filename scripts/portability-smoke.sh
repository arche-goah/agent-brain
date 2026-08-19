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

# Resolve the Python interpreter: the python.org installer on Windows ships ONLY
# `python`, and the Microsoft Store ships a `python3` STUB that resolves in PATH but
# does not run — so probe by RUNNING it, never with `command -v` (measured 2026-08-14:
# a colleague brain had no working `python3`, every reader below returned empty and
# brain-update.sh printed DONE without having done anything).
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
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
if "$PY" "$CORE/scripts/regen-skill-registry.py" --skills "$T/skills" >/dev/null 2>&1 \
   && [ -f "$T/skills/REGISTRY.md" ]; then
  if od -c "$T/skills/REGISTRY.md" | grep -q '\\r'; then
    bad "registry generator writes CRLF (newline= missing)"
  else
    ok "registry generator writes LF"
  fi
else
  bad "registry generator did not run (python present? exit?)"
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
if "$PY" "$CORE/scripts/english-only.py" >/dev/null 2>&1; then
  ok "english-only ratchet runs clean on this OS"
else
  bad "english-only ratchet failed on this OS (path handling? baseline drift?)"
fi
if "$PY" "$CORE/scripts/suite-check.py" "$CORE" >/dev/null 2>&1; then
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

# 9) Shared-memory pair: level 1 (bootup check) and level 2 (live watch). Both are git
#    plumbing plus text munging — the two things that diverge silently between GNU and
#    BSD userland — and level 2 is the only long-running loop the core ships. The watch
#    test builds its own sandbox repo, so this needs no network and no real data.
#    Level 1 against a repo that is NOT cloned must be silent, not an error: an instance
#    that does not take part in shared memory gets nagged at every single start otherwise.
_sm="$(SHARED_MEMORY_REPO="$T/not-cloned" SHARED_MEMORY_STATE="$T/sm-state.json" \
       bash "$CORE/helpers/shared-memory-check.sh" 2>&1)"; _rc=$?
if [ "$_rc" -eq 0 ] && [ -z "$_sm" ]; then
  ok "shared-memory check stays silent without a cloned repo"
else
  bad "shared-memory check on missing repo: rc=$_rc out='$_sm'"
fi
#    A sub-test whose output is thrown away is the same defect it is meant to catch:
#    "it failed" without the line that says why sends the next person back to guessing.
_smw="$(bash "$CORE/scripts/shared-memory-watch-test.sh" 2>&1)"; _rc=$?
if [ "$_rc" -eq 0 ]; then
  ok "shared-memory watch reports a foreign commit AND survives to report the next"
else
  bad "shared-memory watch negative control failed on this OS: $(printf '%s' "$_smw" | tr '\n' ' ' | tail -c 400)"
fi

# 10) invariant-check: pure-Python runner against a fixture register. Three cases in
#     one fixture: a matching baseline (ok), a NEW site (drift, exit 1), and an
#     explicitly named file target that --include does NOT match — the grep-era
#     defect: grep applied --include to command-line files too, so the register
#     carried a dead target and reported ok (P-1 in the runner itself).
mkdir -p "$T/inv/sub"
printf 'alpha MARKER1\n' > "$T/inv/sub/base.py"
printf 'no hit here\n' > "$T/inv/clean.py"
printf 'MARKER1 in explicit target\n' > "$T/inv/explicit.txt"
printf 'root: .\n\n## X-1 — fixture class\npattern: MARKER1\npaths: --include=*.py sub explicit.txt\nknown: sub/base.py=1 explicit.txt=1\nstatus: closed\n' > "$T/inv/reg.md"
_iv="$("$PY" "$CORE/scripts/invariant-check.py" "$T/inv/reg.md" 2>&1)"; _rc=$?
if [ "$_rc" -eq 0 ]; then
  ok "invariant-check: baseline incl. explicit file target holds (grep-era dead target now searched)"
else
  bad "invariant-check baseline: rc=$_rc $(printf '%s' "$_iv" | tr '\n' ' ' | tail -c 300)"
fi
printf 'beta MARKER1\n' > "$T/inv/sub/new.py"
_iv="$("$PY" "$CORE/scripts/invariant-check.py" "$T/inv/reg.md" 2>&1)"; _rc=$?
case "$_rc:$_iv" in
  1:*"NEW site: sub/new.py"*) ok "invariant-check: new site fails loudly (drift ratchet)";;
  *) bad "invariant-check drift: rc=$_rc (expected 1 + NEW site)";;
esac

# 11) stop-verifier v2: reads the TURN from the transcript, not the working tree.
#     Case A: this turn Write()s code containing a marker -> block. Case B: the same
#     marker only in a doc file -> allow. The marker is assembled so this script never
#     contains it literally either.
_mk="$(printf 'TO%s' 'DO')"
_tr="$T/transcript.jsonl"
# node is a Windows binary under Git Bash and cannot open MSYS /tmp paths — hand it
# the mixed form (C:/...); everywhere else cygpath does not exist and the path stays.
_trn="$(cygpath -m "$_tr" 2>/dev/null || printf '%s' "$_tr")"
printf '%s\n' '{"message":{"role":"user","content":"do the thing"}}' > "$_tr"
printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"/x/a.py","content":"# %s later\\n"}}]}}\n' "$_mk" >> "$_tr"
_sv="$(printf '{"transcript_path":"%s","stop_hook_active":false}' "$_trn" | node "$CORE/helpers/stop-verifier.cjs" 2>&1)"
case "$_sv" in
  *'"decision":"block"'*) ok "stop-verifier v2 blocks on a marker written this turn";;
  *) bad "stop-verifier v2 did not block: '$_sv'";;
esac
printf '%s\n' '{"message":{"role":"user","content":"next turn"}}' >> "$_tr"
printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"/x/notes.md","content":"# %s later\\n"}}]}}\n' "$_mk" >> "$_tr"
_sv="$(printf '{"transcript_path":"%s","stop_hook_active":false}' "$_trn" | node "$CORE/helpers/stop-verifier.cjs" 2>&1)"
if [ -z "$_sv" ]; then
  ok "stop-verifier v2 allows doc-only markers AND ignores the previous turn"
else
  bad "stop-verifier v2 blocked wrongly: '$_sv'"
fi

# 12) bootup deadline math: a heading 3 days out must surface as '!! ... in 3 d'.
#     The old line said only 'present — check it' — presence, not effect.
mkdir -p "$T/docs/business"
_d3="$("$PY" -c 'import datetime;print(datetime.date.today()+datetime.timedelta(days=3))')"
printf '## %s — fixture deadline\n' "$_d3" > "$T/docs/business/deadlines.md"
out="$(CLAUDE_PROJECT_DIR="$T" bash "$CORE/helpers/session-bootup.sh" 2>&1)" || true
case "$out" in
  *"!! deadline $_d3 in 3 d"*) ok "bootup computes deadline distance (<7 d escalates)";;
  *) bad "bootup deadline math missing: $(printf '%s' "$out" | grep -i deadline | tail -1)";;
esac

echo
if [ "$fail" -eq 0 ]; then echo "portability-smoke: ALL checks passed"; else echo "portability-smoke: FAILURE (see FAIL lines)"; fi
exit "$fail"
