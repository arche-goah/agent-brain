- **ci-watch: a cancelled job that never got a runner is named in the RED verdict, with the rerun** (test: T1)
  (level: reader; higher: writer - an automatic rerun of such a job, not built because a rerun starts CI time
  without anyone deciding it; debt: ref mode reads a run's overall conclusion only and does not name such jobs).
  Measured on the macOS instance 2026-11-03 on a merge-train PR: `portability (macos-latest)` was cancelled after
  15 minutes with zero steps while every other job passed; the watch said `RED - 1 failing/cancelled check(s)`,
  which reads like a code failure, and only reading the job's steps by hand showed no step had run. The verdict
  stays RED (nothing was tested on that OS); a following line names each cancelled job whose `steps` list is
  empty as "never started (no runner)" and gives `gh run rerun <run> --failed`. `pr checks` now also returns
  `link` (the job URL the note reads). Fixture `scripts/ci-watch-test.sh` +1 case (a never-started macOS job
  named, a failed Ubuntu job not); FAILS against main.
