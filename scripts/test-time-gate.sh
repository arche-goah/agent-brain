#!/usr/bin/env bash
# covers: time-gate
# Fixture test for helpers/time-gate.cjs — both directions, every mode: relative time
# references, estimated durations, daytime attributions, quote stripping, the anchor that
# suppresses the blocking mode, the recorder (--record) and the clock (--clock).
# A gate nobody has seen fire cannot be told apart from a broken one — run this after every
# time-gate or pattern-data change.
# Usage: bash scripts/test-time-gate.sh   (exit 0 = all fixtures pass)
set -u

# A path that travels INSIDE data (a JSON string) is not translated by the shell — on Git Bash
# node would receive /tmp/... and resolve nothing. cygpath states it natively; elsewhere a no-op.
native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

# Two layouts: inside a brain the helper is core/helpers/time-gate.cjs, inside the core repo helpers/.
G=""
for cand in "$ROOT/helpers/time-gate.cjs" "$ROOT/core/helpers/time-gate.cjs"; do
  [ -f "$cand" ] && { G="$cand"; break; }
done
[ -n "$G" ] || { echo "  FAIL time-gate.cjs not found"; exit 1; }

# The fixture brings its OWN language data: it must not measure whichever brain surrounds it,
# and a second language here proves the contract that a language is DATA.
EN="$T/en"; DE="$T/de"; UTC="$T/utc"
mkdir -p "$EN/.claude/rules" "$DE/.claude/rules" "$UTC/.claude/rules"
printf '%s\n' '{"patterns":["\\bgestern\\b","\\bheute\\s+(vormittag|nachmittag|abend)\\b"],' \
  '"duration_patterns":["\\bdauert\\s+(ca\\.|etwa)\\s*\\d+"],' \
  '"dayparts":[{"pattern":"\\b(?:heute\\s+)?nachmittags?\\b|\\bdes\\s+nachmittags\\b","start":12},{"pattern":"\\b(?:heute\\s+)?abends?\\b","start":17}],' \
  '"past_markers":["\\b(war|lief|fund|gefunden)\\b"],"future_markers":["\\b(werde|wird|dann|morgen)\\b"],' \
  '"other_day":["\\b(gestern|morgen)\\b"]}' > "$DE/.claude/rules/time-patterns.json"
printf '%s\n' '{"local_time_only": true}' > "$UTC/.claude/rules/time-patterns.json"

# $1 name, $2 assistant text (json string), $3 block|allow|record, $4 needle, $5 cwd, $6.. args
run_case() {
  local name="$1" text="$2" want="$3" needle="$4" cwd="$5"; shift 5
  local tr="$T/$name.jsonl"
  printf '%s\n' '{"message":{"role":"user","content":"question"}}' > "$tr"
  printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$text" >> "$tr"
  local out
  out="$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$(native "$tr")" "$(native "$cwd")" \
        | node "$G" "$@" 2>&1)"
  case "$want" in
    block|record) case "$out" in *"$needle"*) ok "$name ($want)";; *) bad "$name did not $want: '${out:0:160}'";; esac ;;
    *) [ -z "$out" ] && ok "$name allows" || bad "$name fired wrongly: '${out:0:160}'" ;;
  esac
}

echo "blocking mode (no args):"
run_case en-yesterday '"That was already the case yesterday."' block "Relative time" "$EN"
run_case en-recently '"I fixed that recently."' block "Relative time" "$EN"
run_case en-this-morning '"The collaborator ran this session this morning."' block "Relative time" "$EN"
run_case en-earlier-today '"That landed earlier today in the repo."' block "Relative time" "$EN"
run_case en-n-days-ago '"The pin moved 3 days ago."' block "Relative time" "$EN"
run_case en-future '"We will continue tomorrow morning."' allow "" "$EN"
run_case en-today '"We finished that today."' allow "" "$EN"
run_case en-duration '"This will take about 5 minutes to finish."' block "Estimated duration" "$EN"
run_case en-measured '"The run took 34 s (measured, run record)."' allow "" "$EN"
run_case en-quoted '"The operator wrote \"yesterday\" in the request."' allow "" "$EN"
run_case en-code '"The pattern `yesterday` is a built-in."' allow "" "$EN"
# Anchor suppression (measured 2026-08-20 on the proving instance: 4 of 7 blocks were re-issued
# verbatim, all in replies with a hard time anchor).
run_case anchored-iso '"Ahead since yesterday - core tag of 2026-08-19."' allow "" "$EN"
run_case anchored-clock '"The run was yesterday, stamp 13:45 in the log."' allow "" "$EN"
run_case anchored-commit '"Built yesterday, commit 43e4905 in the core."' allow "" "$EN"
run_case clean '"All done, 34 s from the log."' allow "" "$EN"
# a second language as DATA
run_case de-gestern '"Das war gestern schon so."' block "Relative time" "$DE"
run_case de-gestern-without-data '"Das war gestern schon so."' allow "" "$EN"
run_case de-duration '"Der Sync dauert ca. 5 Minuten."' block "Estimated duration" "$DE"
run_case de-quoted '"Die Schaetzform („dauert ca. 5 Minuten\") ist bekannt."' allow "" "$DE"

echo "recorder (--record):"
run_case rec-unanchored '"That was the case yesterday."' record '"would_block":true' "$EN" --record
run_case rec-anchored '"That was the case yesterday, see 2026-08-19."' record '"would_block":false' "$EN" --record
run_case rec-duration '"This will take about 5 minutes to finish."' record '"family":"duration"' "$EN" --record
run_case rec-nothing '"All done."' record '"record":[]' "$EN" --record

echo "clock (--clock):"
run_clock() { # $1 name, $2 text, $3 now (ISO local), $4 block|allow, $5 cwd
  local tr="$T/$1.jsonl"
  printf '%s\n' '{"message":{"role":"user","content":"question"}}' > "$tr"
  printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$2" >> "$tr"
  local out
  out="$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$(native "$tr")" "$(native "$5")" \
        | TIME_GATE_NOW="$3" node "$G" --clock 2>&1)"
  if [ "$4" = "block" ]; then
    case "$out" in *"TIME-CLOCK"*) ok "$1 blocks";; *) bad "$1 did not block: '${out:0:160}'";; esac
  else
    [ -z "$out" ] && ok "$1 allows" || bad "$1 blocked wrongly: '${out:0:160}'"
  fi
}
run_clock clock-past-en '"This afternoon the run failed on the first turn."' 2026-10-16T09:00:00 block "$EN"
run_clock clock-past-en-reached '"This afternoon the run failed on the first turn."' 2026-10-16T15:10:00 allow "$EN"
run_clock clock-future-en '"I will check this afternoon whether it holds."' 2026-10-16T09:00:00 allow "$EN"
run_clock clock-other-day-en '"Yesterday this afternoon was green."' 2026-10-16T09:00:00 allow "$EN"
run_clock clock-incident-de '"- **Prefix-Analyse, der wichtigste Fund des Nachmittags:** Der Anfang endet hier."' 2026-10-16T10:05:00 block "$DE"
run_clock clock-plan-de '"Heute Abend starte ich die Messung."' 2026-10-16T10:00:00 allow "$DE"
run_clock clock-other-day-de '"Der Lauf war gestern Nachmittag gruen."' 2026-10-16T09:00:00 allow "$DE"
run_clock clock-quoted '"The note says \"this afternoon the run failed\"."' 2026-10-16T09:00:00 allow "$EN"
# local time only: off by default, on through data
run_clock clock-utc-default-off '"The run ended at 18:01 UTC."' 2026-10-16T20:00:00 allow "$EN"
run_clock clock-utc-on '"The run ended at 18:01 UTC."' 2026-10-16T20:00:00 block "$UTC"
run_clock clock-utc-in-code '"The log says `2026-10-16T18:01Z`."' 2026-10-16T20:00:00 allow "$UTC"
run_clock clock-local-time '"The run ended at 20:01."' 2026-10-16T20:30:00 allow "$UTC"

# A false daytime word in an EARLIER message of the turn, already blocked once (the dispatcher's
# echo stands in the transcript), must not block the clean correction that follows (measured
# 2026-10-25: three corrections in a row blocked for an unchangeable word).
run_after_block() { # $1 name, $2 echo line or "", $3 block|allow
  local tr="$T/$1.jsonl"
  printf '%s\n' '{"message":{"role":"user","content":"question"}}' > "$tr"
  printf '{"message":{"role":"assistant","content":[{"type":"text","text":"This afternoon the run was green."}]}}\n' >> "$tr"
  [ -n "$2" ] && printf '{"message":{"role":"user","content":"%s"}}\n' "$2" >> "$tr"
  printf '{"message":{"role":"assistant","content":[{"type":"text","text":"Correction: the run was green at 09:10."}]}}\n' >> "$tr"
  local out
  out="$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s","stop_check":{"label":"CLOCK","marker":"TIME-CLOCK"}}' \
        "$(native "$tr")" "$(native "$EN")" | TIME_GATE_NOW=2026-10-16T09:30:00 node "$G" --clock 2>&1)"
  if [ "$3" = "block" ]; then
    case "$out" in *"TIME-CLOCK"*) ok "$1 blocks";; *) bad "$1 did not block: '${out:0:160}'";; esac
  else
    [ -z "$out" ] && ok "$1 allows" || bad "$1 blocked wrongly: '${out:0:160}'"
  fi
}
run_after_block clock-correction-after-own-block 'Stop hook feedback:\nCLOCK — the clock says 09:30' allow
run_after_block clock-legacy-token-echo 'Stop hook feedback: TIME-CLOCK — the clock says 09:30' allow
run_after_block clock-no-echo-still-blocks '' block
run_after_block clock-other-gate-echo-still-blocks 'Stop hook feedback: OPEN ITEMS — something else' block

# stop_hook_active: silent even with a hit
tr="$T/loop.jsonl"
printf '%s\n' '{"message":{"role":"user","content":"question"}}' '{"message":{"role":"assistant","content":[{"type":"text","text":"That was yesterday."}]}}' > "$tr"
out="$(printf '{"transcript_path":"%s","stop_hook_active":true,"cwd":"%s"}' "$(native "$tr")" "$(native "$EN")" | node "$G" 2>&1)"
[ -z "$out" ] && ok "re-issue pass silent" || bad "re-issue pass fired: '$out'"

echo
[ "$fail" -eq 0 ] && echo "time-gate fixtures: ALL passed" || echo "time-gate fixtures: FAILURE"
exit "$fail"
