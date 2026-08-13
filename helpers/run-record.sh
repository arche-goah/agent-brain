#!/bin/sh
# Record the result of a SCHEDULED run — one line that session start reads.
#
#     run-record.sh <label> ok|fail [note]
#
# WHY. A scheduled run that succeeds announces itself: there's an artifact sitting
# there. One that fails leaves nothing behind — at most a line in a log nobody opens.
# That's exactly how the weekly brain-scan sat dead for days: launchd fired, the run
# got stuck at a permission gate, `launchctl list` kept reporting LastExitStatus 0,
# and the bootup stayed silent (measured 2026-08-06). The launcher's exit code isn't
# fit for this — it says whether the script ran, not whether the run achieved anything.
# So every scheduled run writes its own result here.
#
# WHERE. `<instance>/docs/maintenance/scheduled-runs.tsv`, columns (TAB):
#     epoch  iso  label  ok|fail  note
# The file is runtime state of THIS machine (each has its own scheduler) and does not
# belong in the repo — the instance ignores it.
#
# WHO READS IT. `helpers/session-bootup.sh`: the newest line per label, `fail` becomes `!!`.
# A run that never writes a line stays silent — this channel covers the failing run,
# not the scheduler that never started.
set -u

[ $# -ge 2 ] || { echo "run-record.sh <label> ok|fail [note]" >&2; exit 2; }
label=$1
status=$2
shift 2
hint=${*:-}

case "$status" in ok|fail) ;; *) echo "run-record: status must be ok or fail" >&2; exit 2 ;; esac

root=${BRAIN_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}
dir="$root/docs/maintenance"
file="$dir/scheduled-runs.tsv"
mkdir -p "$dir" || exit 0   # never kill the calling run

# TABs inside the fields would break the columns apart.
label=$(printf '%s' "$label" | tr '\t\n' '  ')
hint=$(printf '%s' "$hint" | tr '\t\n' '  ')

printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$(date '+%F %T')" "$label" "$status" "$hint" >> "$file"

# Trim to the last 200 lines at 400 — a log, not an archive.
lines=$(wc -l < "$file" 2>/dev/null || echo 0)
if [ "$lines" -gt 400 ]; then
  tail -n 200 "$file" > "$file.tmp" && mv "$file.tmp" "$file"
fi
exit 0
