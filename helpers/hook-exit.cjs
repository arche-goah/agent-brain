'use strict';
/**
 * hook-exit.cjs - end a hook process at once, without Node's platform shutdown that can hang.
 *
 * WHY (measured 2026-11-23 on the macOS instance, Node 25.9): a hook that read a large session transcript and then
 * called `process.exit()` hung in Node's shutdown - `Environment::Exit` -> `DisposePlatform` ->
 * `WorkerThreadsTaskRunner::Shutdown` -> `uv_thread_join` - and the harness reported "timed out; blocking because
 * onFailure is block". content-review-gate, 40 runs on a real 7 MB transcript, 10 s cap each: `process.exit` hung 21
 * times, `process.reallyExit` 0 times, a natural end with `process.exitCode` 0 times. Hooks stop mid-flow on purpose
 * (`allow()` deep in a check), so the drop-in has to stop at once like `process.exit` did: `exit(code)` sets the code
 * and ends through `process.reallyExit` (what `process.exit` itself ends with, without the platform teardown), with
 * `process.exit` as the fallback where a Node build has no `reallyExit`. Nothing in the core registers an 'exit'
 * listener, so skipping those events changes nothing.
 *
 * A transcript-reading hook in helpers/ calls this instead of `process.exit` - held by scripts/hook-exit-lint.py.
 * Fixture: scripts/test-hook-exit.sh
 */
function exit(code) {
  const c = Number.isInteger(code) ? code : 0;
  process.exitCode = c;
  if (typeof process.reallyExit === 'function') process.reallyExit(c);
  process.exit(c);
}

module.exports = { exit };
