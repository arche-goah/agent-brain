#!/usr/bin/env bash
# transcript-archive.sh <destination-dir> — pack every Claude Code session transcript
# into one dated archive and prove the archive is complete.
#
# WHY: transcripts are layer 1 of session traceability (rules/working-rules.md) and the
# only verbatim record of what a session read and decided. A system backup usually
# covers the folder, but not at the moment its target is unreachable — this is the
# manual extra grip before a reinstall, a machine move, or a risky cleanup. A tar that
# nobody can open is no backup, so the archive is read back and its file count compared
# against the source; fewer files is a FAILURE (exit 1), not a warning.
#
# PRIVATE CONTENT: transcripts carry everything a session saw — addresses, internal
# names, tool output. The destination must be private: inside a git work tree it is
# REFUSED (an archive there is one `git add -A` away from a remote).
#
# Source: ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects (all projects of this machine).
# Archive: <destination>/claude-transcripts-YYYY-MM-DD-HHMM.tar.gz
# Exit: 0 = archived and verified · 1 = failed or incomplete · 3 = usage / refused.
set -u

DST="${1:-}"
if [ -z "$DST" ]; then
  echo "usage: transcript-archive.sh <destination-dir>   (a private place, never a repo)" >&2
  exit 3
fi
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# Git Bash: a `C:\...` path has a colon, which GNU tar reads as host:path — use the
# POSIX spelling wherever cygpath exists.
if command -v cygpath >/dev/null 2>&1; then
  CFG="$(cygpath -u "$CFG")"; DST="$(cygpath -u "$DST")"
fi
SRC="$CFG/projects"

[ -d "$SRC" ] || { echo "ERROR: no transcript folder at $SRC" >&2; exit 1; }
[ -d "$DST" ] || { echo "ERROR: destination $DST does not exist" >&2; exit 1; }
if git -C "$DST" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "REFUSED: $DST is inside a git work tree — transcripts are private, pick a place outside any repo" >&2
  exit 3
fi

OUT="$DST/claude-transcripts-$(date '+%Y-%m-%d-%H%M').tar.gz"
# counted BEFORE packing: a file a running session creates meanwhile may land in the
# archive (more is fine), but nothing that existed may be missing from it
N_SRC=$(find "$SRC" -type f | wc -l | tr -d ' ')
echo "source : $SRC ($N_SRC files, $(du -sh "$SRC" | cut -f1))"
echo "archive: $OUT"
tar -czf "$OUT" -C "$CFG" projects || { echo "ERROR: tar failed" >&2; exit 1; }

N_TAR=$(tar -tzf "$OUT" | awk '!/\/$/ { n++ } END { print n + 0 }')
echo "size   : $(du -h "$OUT" | cut -f1)"
echo "verify : $N_TAR files in the archive / $N_SRC in the source"
if [ "$N_TAR" -ge "$N_SRC" ] && [ "$N_SRC" -gt 0 ]; then
  echo "OK — archive complete."
  exit 0
fi
echo "FAIL — the archive holds fewer files than the source (or the source is empty)." >&2
exit 1
