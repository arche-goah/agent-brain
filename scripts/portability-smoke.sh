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

# 11b) class-gate: block on a code turn, silent on a doc-only turn, silent in
#      cooldown. Proven 14 days on one instance before moving here — these three
#      fixtures pin the mechanics that made it work (turn window, doc filter,
#      3-turn cooldown read from its own replayed feedback).
_tg="$T/gate-transcript.jsonl"
_tgn="$(cygpath -m "$_tg" 2>/dev/null || printf '%s' "$_tg")"
printf '%s\n' '{"message":{"role":"user","content":"build the thing"}}' > "$_tg"
printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/x/tool.py","new_string":"y = 2"}}]}}' >> "$_tg"
_cg="$(printf '{"transcript_path":"%s","stop_hook_active":false}' "$_tgn" | node "$CORE/helpers/class-gate.cjs" 2>&1)"
case "$_cg" in
  *CLASS-GATE*) ok "class-gate blocks after a code turn";;
  *) bad "class-gate did not block: '$_cg'";;
esac
printf '%s\n' '{"message":{"role":"user","content":"Stop hook feedback: CLASS-GATE (fires because work succeeded)"}}' >> "$_tg"
printf '%s\n' '{"message":{"role":"user","content":"next order"}}' >> "$_tg"
printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/x/tool2.py","new_string":"z = 3"}}]}}' >> "$_tg"
_cg="$(printf '{"transcript_path":"%s","stop_hook_active":false}' "$_tgn" | node "$CORE/helpers/class-gate.cjs" 2>&1)"
if [ -z "$_cg" ]; then
  ok "class-gate stays silent in the 3-turn cooldown"
else
  bad "class-gate fired inside cooldown: '$_cg'"
fi
printf '%s\n' '{"message":{"role":"user","content":"turn 2"}}' >> "$_tg"
printf '%s\n' '{"message":{"role":"user","content":"turn 3"}}' >> "$_tg"
printf '%s\n' '{"message":{"role":"user","content":"turn 4, docs please"}}' >> "$_tg"
printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"/x/notes.md","content":"docs"}}]}}' >> "$_tg"
_cg="$(printf '{"transcript_path":"%s","stop_hook_active":false}' "$_tgn" | node "$CORE/helpers/class-gate.cjs" 2>&1)"
if [ -z "$_cg" ]; then
  ok "class-gate ignores a doc-only turn (cooldown also elapsed)"
else
  bad "class-gate blocked a doc-only turn: '$_cg'"
fi

# 11b2) class-gate shows paths RELATIVE to cwd also when the transcript carries
#       Windows backslash paths — `cwd + '/'` never matched those, so the gate
#       printed absolute paths (cosmetic, measured 2026-08-19 on the Windows
#       instance). Pure string handling, so this runs on every OS.
printf '%s\n' '{"message":{"role":"user","content":"windows turn"}}' > "$_tg"
printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"C:\\x\\brain\\scripts\\tool3.py"}}]}}' >> "$_tg"
_cg="$(printf '{"transcript_path":"%s","cwd":"C:\\\\x\\\\brain","stop_hook_active":false}' "$_tgn" | node "$CORE/helpers/class-gate.cjs" 2>&1)"
case "$_cg" in
  *"Touched this turn: scripts/tool3.py"*) ok "class-gate strips the cwd prefix from backslash paths";;
  *) bad "class-gate backslash strip: '$(printf '%s' "$_cg" | grep -o 'Touched this turn: [^\\n\"]*' | head -1)'";;
esac

# 11c) the register template must parse in the runner (a seed that the runner
#      rejects would ship a broken fixed step of the release catch-up).
mkdir -p "$T/regbrain/docs/maintenance"
cp "$CORE/templates/invariants.md" "$T/regbrain/docs/maintenance/invariants.md"
_rg="$("$PY" "$CORE/scripts/invariant-check.py" "$T/regbrain/docs/maintenance/invariants.md" 2>&1)"; _rc=$?
if [ "$_rc" -eq 0 ]; then
  ok "invariant register template parses clean in the runner"
else
  bad "register template rejected: rc=$_rc $(printf '%s' "$_rg" | tr '\n' ' ' | tail -c 200)"
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

# 13) hook coverage: a template hook that no settings scope wires must be reported
#     (the v1.3.12 class-gate shipped consumed-but-wired-nowhere on a live brain);
#     a fully wired brain must stay silent. CLAUDE_CONFIG_DIR points into the
#     fixture so the runner's real user settings can never leak into the check.
mkdir -p "$T/hookbrain/core/templates" "$T/hookbrain/core/helpers" "$T/hookbrain/.claude" "$T/nocfg"
cp "$CORE/templates/settings.json" "$T/hookbrain/core/templates/"
cp "$CORE"/helpers/*.cjs "$CORE"/helpers/*.sh "$T/hookbrain/core/helpers/" 2>/dev/null
printf '{}\n' > "$T/hookbrain/.claude/settings.json"
_hc="$(CLAUDE_CONFIG_DIR="$T/nocfg" "$PY" "$CORE/scripts/hook-coverage.py" "$T/hookbrain" 2>&1)"; _rc=$?
case "$_rc:$_hc" in
  1:*"Stop:"*class-gate.cjs*) ok "hook-coverage flags an unwired template hook (exit 1)";;
  *) bad "hook-coverage missing-hook case: rc=$_rc out='$(printf '%s' "$_hc" | head -1)'";;
esac
cp "$CORE/templates/settings.json" "$T/hookbrain/.claude/settings.json"
_hc="$(CLAUDE_CONFIG_DIR="$T/nocfg" "$PY" "$CORE/scripts/hook-coverage.py" "$T/hookbrain" 2>&1)"; _rc=$?
if [ "$_rc" -eq 0 ] && [ -z "$_hc" ]; then
  ok "hook-coverage stays silent on a fully wired brain"
else
  bad "hook-coverage false alarm: rc=$_rc out='$(printf '%s' "$_hc" | head -1)'"
fi
#     And the bootup voices it: the fixture brain gets the template but an empty
#     settings file — the !! line is the carrier that repeats until it is fixed.
printf '{}\n' > "$T/hookbrain/.claude/settings.json"
out="$(CLAUDE_PROJECT_DIR="$T/hookbrain" CLAUDE_CONFIG_DIR="$T/nocfg" bash "$CORE/helpers/session-bootup.sh" 2>&1)" || true
case "$out" in
  *"!! hooks in the core template but not wired here:"*) ok "bootup voices unwired template hooks";;
  *) bad "bootup hook-coverage line missing";;
esac

# --- 12. the mechanisms prove themselves, on every OS ------------------------
# Fixtures instead of assertions about fixtures: each suite runs every helper it covers
# in BOTH directions. A helper that stops firing on one platform is otherwise invisible
# — it looks exactly like a helper that had nothing to say.
for suite in test-guards test-stop-checks test-session-helpers test-stop-dispatcher \
             test-premise-gate; do
  if [ -f "$CORE/scripts/$suite.sh" ]; then
    if _out="$(cd "$CORE" && bash "scripts/$suite.sh" 2>&1)"; then
      ok "$suite"
    else
      bad "$suite: $(printf '%s' "$_out" | grep -E '^  FAIL' | head -2 | tr '\n' ' ')"
    fi
  fi
done

# --- 13. hook-coverage understands indirection -------------------------------
# A dispatcher runs several checks itself, so settings name only the dispatcher.
# Matching on filenames alone reported those helpers as missing every session (measured
# 2026-08-20) — and a warning that is always there stops being a signal. Both halves are
# required: the dispatcher must be WIRED and the helper REGISTERED.
mkdir -p "$T/dispbrain/.claude/rules" "$T/dispbrain/core"
cp -R "$CORE/helpers" "$T/dispbrain/core/helpers"
cp -R "$CORE/templates" "$T/dispbrain/core/templates"
printf '{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"node \\"$CLAUDE_PROJECT_DIR/core/helpers/stop-dispatcher.cjs\\""}]}]}}\n' \
  > "$T/dispbrain/.claude/settings.json"
printf '{"checks":[{"label":"C","marker":"CLASS-GATE","cmd":"core/helpers/class-gate.cjs","mode":"block"}]}\n' \
  > "$T/dispbrain/.claude/rules/stop-checks.json"
_hc="$(CLAUDE_CONFIG_DIR="$T/nocfg" "$PY" "$CORE/scripts/hook-coverage.py" "$T/dispbrain" 2>&1)"; _rc=$?
case "$_hc" in
  *class-gate*) bad "hook-coverage still reports a dispatcher-registered helper";;
  *) ok "hook-coverage accepts a helper registered behind a wired dispatcher";;
esac
# The bootup runs the machinery check itself, so no instance has to remember a settings
# line (third-instance proposal 2026-08-20, after two machines were measured without it).
# A template entry would have reached only newly bootstrapped brains; this reaches every
# brain that consumes the core. Asserted on the OUTPUT, because a call that silently
# does nothing is the failure this whole strand is about.
_bo="$(CLAUDE_PROJECT_DIR="$T/hookbrain" CLAUDE_CONFIG_DIR="$T/nocfg" bash "$CORE/helpers/session-bootup.sh" 2>&1)" || true
case "$_bo" in
  *brain-check:*) ok "bootup runs the machinery check itself";;
  *) bad "bootup does not run brain-check — an instance would have to remember it";;
esac

# A template hook in core/SCRIPTS must be demanded just like one in core/helpers.
# Measured 2026-08-20: brain-check.sh lives in scripts/, so a brain that never wired it
# was reported as fully covered — the check for "shipped but not wired" was blind to
# exactly that shape. The case builds its OWN template: asserting a capability against
# whatever the real template happens to contain measures that content instead.
mkdir -p "$T/scriptbrain/.claude" "$T/scriptbrain/core/templates" "$T/scriptbrain/core/scripts"
cp -R "$CORE/helpers" "$T/scriptbrain/core/helpers"
cp "$CORE/scripts/brain-check.sh" "$T/scriptbrain/core/scripts/brain-check.sh"
printf '%s' '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/core/scripts/brain-check.sh\" --brief"}]}]}}' \
  > "$T/scriptbrain/core/templates/settings.json"
printf '{}\n' > "$T/scriptbrain/.claude/settings.json"
_hc="$(CLAUDE_CONFIG_DIR="$T/nocfg" "$PY" "$CORE/scripts/hook-coverage.py" "$T/scriptbrain" 2>&1)"
case "$_hc" in
  *brain-check.sh*) ok "hook-coverage demands a template hook from core/scripts";;
  *) bad "hook-coverage blind to core/scripts template hooks";;
esac

# ... and the same helper WITHOUT the registration must still be reported, otherwise the
# acceptance above would be a way to silence the check by writing an empty file.
printf '{"checks":[]}\n' > "$T/dispbrain/.claude/rules/stop-checks.json"
_hc="$(CLAUDE_CONFIG_DIR="$T/nocfg" "$PY" "$CORE/scripts/hook-coverage.py" "$T/dispbrain" 2>&1)"
case "$_hc" in
  *class-gate*) ok "hook-coverage still flags an unregistered helper";;
  *) bad "hook-coverage went blind: an unregistered helper was accepted";;
esac

echo
if [ "$fail" -eq 0 ]; then echo "portability-smoke: ALL checks passed"; else echo "portability-smoke: FAILURE (see FAIL lines)"; fi
exit "$fail"
