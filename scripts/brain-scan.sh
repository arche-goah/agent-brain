#!/bin/zsh
# Brain-Scan launcher — ONLY for the SCHEDULED run on macOS/Linux.
#
# == PLATFORM (clarified 2026-08-04, operator decision) ==========================
# This script requires zsh AND a scheduler (launchd/cron). Neither exists on
# Windows — it is NOT the way there and is not being ported either: a ported
# launcher would still have no scheduler to call it.
#
# The platform-independent entry point is the workflow tool, directly in the
# session:
#     Workflow({ scriptPath: "core/workflows/brain-scan.js", args: { date: "<YYYY-MM-DD>" } })
# (verified 2026-08-04 on Windows/Git-Bash together with kohaerenz-scan). The scan
# itself is platform-neutral — only this scheduling wrapper around it is not.
#
# Before every start, apply `core/rules/intelligence.md` -> "repeat runs":
# read the last run's artifacts -> check freshness -> only then start.
# ==================================================================================
#
# Called by the instance's scheduler (launchd/cron, label defined there) DAILY plus
# on login/boot; but only runs if the last successful scan is >= 7 days old
# (catch-up in case the machine was offline).
# Due-ness hangs off the newest REPORT (docs/research/brain-scan/scan-*.md), not a
# stamp next to it: the stamp only came from here and stood still on every
# in-session run (full audit, direct workflow call) — two sources for one fact, and
# the second one drifted (measured 2026-08-06: stamp 8d, report 5d).
# Force manually: BRAIN_SCAN_FORCE=1 scripts/brain-scan.sh
# Instance config via env: BRAIN_DIR (required in scheduler context), CLAUDE_BIN (optional).
set -u
CLAUDE="${CLAUDE_BIN:-$(command -v claude)}"
REPO="${BRAIN_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"
# CORE = this checkout, INSTANCE = REPO (AGENTS.md #3) — as a submodule CORE is a
# subdirectory of REPO, as a standalone clone it is not. So resolve it independently.
CORE="$(cd -- "$(dirname -- "$0")/.." && pwd)"
LOG_DIR="$REPO/docs/research/brain-scan"
INTERVAL=$((7 * 24 * 3600))
mkdir -p "$LOG_DIR"

if [[ -z "${BRAIN_SCAN_FORCE:-}" ]]; then
  latest=$(ls -t "$LOG_DIR"/scan-*.md 2>/dev/null | head -1)
  if [[ -n "${latest:-}" ]]; then
    # mtime, portably: GNU (Linux/Git-Bash) `-c %Y` vs BSD (macOS) `-f %m`. Cannot be
    # chained with `||` — GNU reads `-f` as --file-system, fails on the %m operand and
    # still prints prose for the file, so both branches ran and `m` held "  File: ..."
    # plus the epoch. Under `set -u` below that is an abort inside `(( ))`, and it
    # stands BEFORE every run-record line: the scheduled run would have died silently
    # on Linux — exactly the class this script is supposed to report. So check first,
    # then compute.
    m=$(stat -c %Y "$latest" 2>/dev/null) || true
    [[ "$m" =~ ^[0-9]+$ ]] || m=$(stat -f %m "$latest" 2>/dev/null) || true
    [[ "$m" =~ ^[0-9]+$ ]] || m=0
    (( $(date +%s) - m < INTERVAL )) && exit 0
  fi
fi

DATE=$(date +%F)
cd "$REPO" || exit 1
{
  echo "=== brain-scan start $(date '+%F %T') ==="
  # `--allowedTools Workflow` is required: without it the headless run stalls at the
  # harness gate "Review dynamic workflow before running" and only returns
  # {"error": "Review dynamic workflow before running"} — measured 2026-08-06, even for
  # a SAVED workflow without a single agent; `--permission-mode acceptEdits` alone is
  # not enough. The list is additive (Bash/Read/Edit stay allowed), and the flag is
  # variadic — the prompt must come BEFORE it, or it swallows it.
  "$CLAUDE" -p \
    "Run the saved workflow 'brain-scan': Workflow({name:'brain-scan', args:{date:'$DATE'}, run_in_background:false}). This is an ordered, recurring task (docs/maintenance/brain-scan-auftraege.md, F10 from: operator 2026-07-29). Wait for the result and print ONLY at the end: report path, summary, topFindings." \
    --permission-mode acceptEdits --allowedTools Workflow
  rc=$?
  # Due stays due as long as no report sits on disk — the next run gates on that itself
  # now (freshness = newest report). Finding 2026-08-04: `claude -p` returned exit 0
  # even though the run stalled at the gate and NO report was produced; a stamp on the
  # exit code alone would have suppressed the next run for 7 days. Success is what is
  # on disk.
  # ... and the same verdict goes to session start as ONE line. Without this channel
  # the failure only sits here in the log that nobody opens (2026-08-06: six days of
  # daily failures, `launchctl list` reported LastExitStatus 0 throughout).
  RECORD="$CORE/helpers/run-record.sh"
  if (( rc == 0 )) && [[ -s "$LOG_DIR/scan-$DATE.md" ]]; then
    echo "Report: $LOG_DIR/scan-$DATE.md"
    BRAIN_DIR="$REPO" sh "$RECORD" brain-scan ok "scan-$DATE.md" 2>/dev/null
  else
    echo "no report: rc=$rc, $LOG_DIR/scan-$DATE.md missing or empty — next due run stays due"
    BRAIN_DIR="$REPO" sh "$RECORD" brain-scan fail "rc=$rc, no report — details: docs/research/brain-scan/run.log" 2>/dev/null
  fi
  echo "=== brain-scan end $(date '+%F %T') exit=$rc ==="
} >> "$LOG_DIR/run.log" 2>&1
