#!/usr/bin/env bash
# autonomy-diagnose-run.sh — run the autonomy diagnosis on a brain, unattended, and ALWAYS end with
# something to read: a report when it works, and a named reason per step when it does not.
#
# WHY (2026-10-16): the diagnosis is meant for a brain whose AI asks before every step, run by its
# human in a plain terminal without that AI. "It ran here" proves little — the machine on the other
# side has its own Claude Code version, Python name, paths and a brain on an older core. So every step
# is checked before it runs, runs on its own, and logs its exit code and error text. A step that
# cannot run is SKIPPED with the reason; nothing aborts the run. The run folder is the debug unit:
# send it as it is.
#
# Steps:
#   python  find a Python that RUNS (a Windows Store `python3` stub resolves in PATH but does not run)
#   script  autonomy-diagnose.py -> autonomy-report.md (exact numbers; no model)
#   prompt  the agent brief: the --prompt file from its marker line `<!-- agent-brief -->` on (a file
#           without the marker is used whole; a leading `---` would be read as a CLI option, so the
#           brief always goes in on stdin)
#   claude  claude found, version, and every flag the agent run needs present in `claude --help`
#   agent   claude -p, safe mode, read-only tools, no prompts -> diagnose-bericht.md
#
# Usage (in the brain folder, Git Bash or a macOS/Linux terminal):
#   bash autonomy-diagnose-run.sh --prompt FILE [--brain DIR]
# Output: ~/diagnose/run-<timestamp>/ with summary.txt, env.txt, run.log, the two reports and the
#   stderr of every step. Exit 0 always.
# Seams for the fixture only (nothing in normal use sets them): DIAG_OUT_ROOT, DIAG_PYTHONS,
#   DIAG_CLAUDE, DIAG_SCRIPT_URL. On Windows, DIAG_OUT_ROOT must be a native path (OS-3).
set -u

BRAIN="$PWD"
BRIEF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --brain) BRAIN="${2:-}"; shift 2 ;;
    --prompt) BRIEF="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1 (ignored)"; shift ;;
  esac
done

here="$(cd "$(dirname "$0")" && pwd)"
OUT="${DIAG_OUT_ROOT:-$HOME/diagnose}/run-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT" || { echo "cannot create $OUT"; exit 0; }
LOG="$OUT/run.log"
SUM="$OUT/summary.txt"
: > "$SUM"
log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >> "$LOG"; }
result() { # $1 step, $2 ok|SKIPPED|FAILED, $3 detail
  printf '%-7s %-8s %s\n' "$1" "$2" "$3" >> "$SUM"; log "STEP $1: $2 — $3"
}

# ---------- environment (for debugging from the other side)
{
  echo "date:        $(date)"
  echo "os:          $(uname -a 2>/dev/null)"
  echo "bash:        ${BASH_VERSION:-?}"
  echo "brain:       $BRAIN"
  echo "brain git:   $(git -C "$BRAIN" rev-parse --short HEAD 2>&1 | head -1)"
  echo "core:        $(git -C "$BRAIN/core" describe --tags --always 2>&1 | head -1)"
  echo "git:         $(git --version 2>&1 | head -1)"
  echo "curl:        $(curl --version 2>&1 | head -1)"
  echo "PATH:        $PATH"
} > "$OUT/env.txt" 2>&1
[ -f "$BRAIN/CLAUDE.md" ] || log "WARN no CLAUDE.md in $BRAIN — is this the brain folder? (the run continues)"

# ---------- python: probe by RUNNING it
PY=""
for c in ${DIAG_PYTHONS:-python3 python py}; do
  v="$("$c" -c 'import sys; print(sys.version.split()[0])' 2>>"$OUT/python.stderr")" && { PY="$c"; break; }
  log "python candidate '$c' does not run"
done
if [ -n "$PY" ]; then
  result python ok "Python $v via '$PY'"; echo "python:      $v via $PY" >> "$OUT/env.txt"
else
  result python FAILED "no working Python (tried: ${DIAG_PYTHONS:-python3 python py}); the script step is skipped, the agent still runs"
fi

# ---------- script
SCRIPT="$here/autonomy-diagnose.py"
if [ -n "$PY" ]; then
  if [ ! -f "$SCRIPT" ]; then
    SCRIPT="$OUT/autonomy-diagnose.py"
    url="${DIAG_SCRIPT_URL:-https://raw.githubusercontent.com/arche-goah/agent-brain/main/scripts/autonomy-diagnose.py}"
    curl -fsSL "$url" -o "$SCRIPT" 2>>"$OUT/script.stderr" || log "download of $url failed (rc $?)"
  fi
  if [ -f "$SCRIPT" ]; then
    "$PY" "$SCRIPT" --repo "$BRAIN" --out "$OUT/autonomy-report.md" >>"$LOG" 2>>"$OUT/script.stderr"; rc=$?
    if [ $rc -eq 0 ] && [ -s "$OUT/autonomy-report.md" ]; then
      result script ok "autonomy-report.md, $(grep -c '' "$OUT/autonomy-report.md") lines"
    else
      result script FAILED "rc $rc — see script.stderr: $(tail -1 "$OUT/script.stderr" 2>/dev/null)"
    fi
  else
    result script FAILED "autonomy-diagnose.py neither next to this runner nor downloadable — see script.stderr"
  fi
else
  result script SKIPPED "no Python"
fi

# ---------- prompt
PROMPT="$OUT/prompt.md"
if [ -z "$BRIEF" ]; then
  result prompt FAILED "no --prompt FILE given"
elif [ ! -f "$BRIEF" ]; then
  result prompt FAILED "--prompt $BRIEF does not exist"
else
  if grep -q '^<!-- agent-brief -->' "$BRIEF"; then
    sed -n '/^<!-- agent-brief -->/,$p' "$BRIEF" | sed '1d' > "$PROMPT"; how="from the agent-brief marker"
  else
    cp "$BRIEF" "$PROMPT"; how="whole file (no agent-brief marker)"
  fi
  if [ -s "$PROMPT" ]; then
    result prompt ok "$(grep -c '' "$PROMPT") lines, $how, $BRIEF ($(git -C "$(dirname "$BRIEF")" log -1 --format='%h %cs' -- "$BRIEF" 2>/dev/null))"
  else
    result prompt FAILED "$BRIEF gives an empty brief"
  fi
fi

# ---------- claude: present, and every flag the run needs
CL="${DIAG_CLAUDE:-claude}"
CLAUDE_OK=""
if command -v "$CL" >/dev/null 2>&1; then
  cv="$("$CL" --version 2>&1 | head -1)"; echo "claude:      $cv" >> "$OUT/env.txt"
  help="$("$CL" --help 2>&1)"
  missing=""
  # Every flag the agent run needs; a literal list (no word-split variable) and a shell match (no
  # grep on help text that may carry control characters — OS-5, OS-10).
  for f in --safe-mode --tools --add-dir --permission-prompts --no-session-persistence; do
    case "$help" in *"$f"*) ;; *) missing="$missing $f" ;; esac
  done
  if [ -z "$missing" ]; then
    CLAUDE_OK=1; result claude ok "$cv"
  else
    result claude FAILED "$cv lacks:$missing — update Claude Code (claude update), then run again"
  fi
else
  result claude FAILED "'$CL' not found in PATH"
fi

# ---------- agent
if [ -n "$CLAUDE_OK" ] && [ -s "$PROMPT" ]; then
  MEM=""
  [ -n "$PY" ] && [ -f "$SCRIPT" ] && MEM="$("$PY" "$SCRIPT" --repo "$BRAIN" --memory-dir 2>>"$OUT/agent.stderr")"
  set -- --safe-mode --tools "Read,Grep,Glob" --add-dir "$OUT" --permission-prompts none --no-session-persistence
  [ -n "$MEM" ] && [ -d "$MEM" ] && set -- "$@" --add-dir "$MEM"
  [ -n "$MEM" ] && [ ! -d "$MEM" ] && log "memory folder $MEM does not exist — the agent reads no memory"
  log "agent: $CL -p $*"
  t0=$(date +%s)
  (cd "$BRAIN" && "$CL" -p "$@" < "$PROMPT" > "$OUT/diagnose-bericht.md" 2>>"$OUT/agent.stderr"); rc=$?
  dt=$(( $(date +%s) - t0 ))
  if [ $rc -eq 0 ] && [ -s "$OUT/diagnose-bericht.md" ]; then
    result agent ok "diagnose-bericht.md, $(grep -c '' "$OUT/diagnose-bericht.md") lines, ${dt} s"
  else
    result agent FAILED "rc $rc after ${dt} s — see agent.stderr: $(tail -1 "$OUT/agent.stderr" 2>/dev/null)"
  fi
else
  result agent SKIPPED "needs a working claude and a prompt (see the two lines above)"
fi

echo
cat "$SUM"
echo
echo "Run folder: $OUT"
echo "Send this whole folder (or summary.txt + the two .md reports) to whoever asked for the diagnosis."
exit 0
