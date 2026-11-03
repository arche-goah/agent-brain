- **mechanism-guard: a `|` the shell never runs as a pipe separates nothing** (test: T1) (level: reader; higher: design —
  one cut before every rule instead of ten separator patterns; debt: a `|` inside `$( … )` in double quotes stays a pipe,
  as the shell runs it). Measured on the macOS instance 2026-11-03: `grep -n "Monitor\|collab-watch.sh" …` and
  `sed … ci-watch.sh | grep "usage\|ci-watch.sh"` were held as "a waiting script in the foreground" — the rule read
  `|collab-watch.sh` as a pipe into the script. `literalPipes()` turns an escaped `\|` and a `|` inside quotes into `¦`
  in the text the rules read; real pipes stay. Fixture +3 in `test-guards.sh` (single-quoted case red on the old guard).
