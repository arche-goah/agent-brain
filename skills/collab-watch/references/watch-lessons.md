# Watch lessons — why the collaboration watch is built the way it is

Every item was measured on the proving instance before it became a mechanism. Each names
the invariant, the failure it prevents, and where it is carried now. A watcher that fails
any of these does not crash — it goes quiet, and quiet looks like a good day.

## Channel

1. **A watch polls the channel the EVENT appears on, not the one the artifact does.**
   A watch on the open-PR list missed a retest result posted as a comment on a merged PR
   (the normal case once work is under way), and later a merge of our PR by the other
   party (a merged PR leaves the open list). Carried by `repo-activity-watch.sh`: PRs,
   merges, conversation comments, inline review comments. Not carried: review verdicts
   without inline comments — `watch-pr.sh` for a PR under review.
2. **A merge is judged by who merged it, not who wrote it.** The other party merging our
   PR is exactly the event wanted. Carried by `repo-activity-filter.py` (`mergedBy`).

## Filters

3. **Never filter by the operator's login.** All own machines and parallel sessions push
   under one account; the filter swallows the other own machine. Default self filter is
   `-` (matches nobody). Proven by the negative control in `test-repo-activity-watch.sh`.
4. **A filter is proven with a negative control before arming.** Count the same window
   unfiltered: unfiltered n>0 and filtered 0 means the filter is wrong. Resolve identities
   against your OWN repos (who actually authored here), never against a global name
   lookup — a 200 on a username proves that login exists, not that it is the person.
5. **A role word must not steer a filter.** A scope named after a role carried one
   collaborator's login; when a second one joined, it would have dropped him for good.
   Parties are DATA (`parties` in the instance config), scopes select by party, and a
   scope that selects an own machine is refused (one account, not separable by login).
6. **A filtered event is gone, not deferred.** Cursors advance before any filter sees a
   line. The arm script and the watcher say so in a NOTE whenever a filter is active.
7. **An unknown sender passes the filter.** A shared-memory find without a recognisable
   party is a finding, not noise.

## Cursors and locks

8. **The cursor is a file.** Whatever happened while nothing ran is reported at the next
   start; a missing cursor is seeded loudly ("older activity is NOT reported").
9. **GitHub's `since` is inclusive.** With cursor = newest timestamp, the newest comment
   re-enters every round. Strict `>` in the filter. Repeat noise trains readers to ignore
   the watcher — the same blindness it exists to prevent.
10. **One cursor per watch.** Two cadences sharing one cursor: the faster advances it past
    the slower one's events. Carried by the tag (unique, checked by the plan step; the
    fixture proves the swallowing).
11. **The watch has its own shared-memory cursor.** Shared with the session-start check,
    ANY session's start on the machine consumes a find before the designated watcher sees
    it. `collab-watch.sh` keeps cursor AND lock under `COLLAB_WATCH_STATE` — moving only
    the cursor leaves the lock where another session holds it, and the watch is refused.
12. **Claim a lock atomically, release only your own.** `noclobber` claim (check-then-write
    lets two sessions both pass); an unconditional release deletes a lock another session
    took over legitimately, and the next arm starts an invisible second watcher.
13. **"already armed" is the tool's claim, not a measurement.** `kill -0` proves a process
    lives, not that a session holds it — measured: an orphaned watcher held the lock while
    no session read its output. Check `ps` and the parent chain before naming a session.

## Process lifetime

14. **A watcher can die without a word.** Its Monitor task said `running`, the process was
    gone, for over an hour. `watch-supervisor.sh` turns every death into one line and
    restarts with a doubling backoff.
15. **No parent, no watch.** Every loop checks the process that started it and exits when
    it is gone; an orphan otherwise polls forever and keeps the locks.
16. **Teardown must not depend on pkill.** Killing a supervisor first re-parents its
    payload, and `pkill -P` then reports success against nothing; Git Bash on Windows has
    no `pkill` at all. The supervisor kills its own child on TERM — proven in its fixture.
    And a TERM trap must EXIT: a trap that only cleans up swallows the signal, and the arm
    process kept running with every supervisor gone (found in this script's live smoke;
    `test-repo-activity-watch.sh` now kills the arm script and checks the tree and locks).
17. **A filter on a pipe must flush.** A watch ending in `awk` without `fflush()` holds the
    event line in a buffer; the notification never comes. And never pipe a filter onto ONE
    background job: `$!` becomes the filter's pid and cleanup kills the wrong process —
    filter the whole stdout instead (`exec > >(...)`).
18. **A blind poll must say so.** Every API call failing prints nothing; the watcher probes
    reachability each round and reports `WATCH-ERROR` once per outage.

## Attribution

19. **Own account ≠ the other own machine.** An event under the operator's login may come
    from a parallel session on THIS machine. Check `parallel-sessions.sh` and the
    local-branch mark before naming a source; a parallel session's PR is handled by its
    author session (otherwise two sessions race on one merge).
20. **A poll with several commits names more than one sender.** Read the range's log for
    the parties before writing a name.
