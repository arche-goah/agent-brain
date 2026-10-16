- **Session start: is this instance ready to watch?** (test: T1) New `scripts/watch-readiness.py`, run by `session-bootup.sh` right after the open-items list. On an instance that takes part in shared memory (clone, `SHARED_MEMORY_SELF` or `collab-watch.json` present) it names:
  - a missing, unfilled or broken `.claude/rules/collab-watch.json`;
  - an unset `SHARED_MEMORY_SELF`;
  - every repo where a PR for this instance arrived in the last 7 days and that the standing watch does not poll.

  It is silent when the instance is ready or outside shared memory; read-only, no network (it reads the PR items `open-items.py` stored this start). Measured 2026-10-16 on three instances (the operator: the second macOS machine had no automatic PR and shared-memory watch):
  - the freshly bootstrapped one had neither config nor self id;
  - all three missed repos where their own PRs arrived;
  - the first live run on the macOS instance named `brain-shared-memory`, whose PRs no watch polled.

  Fixture `test-watch-readiness.sh`: outside shared memory silent · fresh brain names both gaps · template copy names its placeholders · ready instance silent (placeholders inside `_comment` do not count, self id read from the settings env) · unwatched PR repo named, watched and out-of-window ones not · broken JSON named.
