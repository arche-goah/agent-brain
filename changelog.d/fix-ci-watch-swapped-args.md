- **ci-watch: the swapped pr form `pr <number> <owner/repo>` is read, not refused** (test: T1) (level: reader; higher: writer - named flags (`--repo`, `--pr`) would make the order irrelevant, not done: every caller in skills and docs uses positional args, a flag form would be a second grammar; debt: none; the second reader of the call, watch-gate.cjs, now shares one parser `ciWatchCall` for both orders)
  Measured on the macOS instance: three dead watches in two weeks from the same wrong order (2026-10-27; twice on
  2026-11-11, once by a background agent), each needing a restart before the PR had a watch. A number and an
  owner/name cannot be confused, so the script swaps them and says so on stderr (`read as: pr <repo> <n>`).
  Fixture `scripts/ci-watch-test.sh` +2 (red against main, green now); the `pr 33 --repo x` refusal stays.
  Windows review: watch-gate read only `pr <repo> <n>`, so a running swapped-form watch was reported as "no CI watch";
  one parser `ciWatchCall` replaces its two regexes, `scripts/test-watch-gate.sh` +4 (two red on the old gate).
