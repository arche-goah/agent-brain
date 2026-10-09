---
name: shared-memory-watch
description: Live watch on the shared-memory repo while a session runs — arms the persistent watcher so commits from other instances or collaborators surface by themselves instead of being discovered at the next session start. Use right after pushing a shared-memory entry that expects a reaction (a question, an open point, a request to counter-check), and once at the start of a session that visibly works with shared memory or cross-instance coordination. NOT a headless daemon — it lives and dies with the session.
---

# Shared-Memory Live Watch (level 2)

A shared repo that is only read when someone remembers to read it is shared in name
only. The failure mode is silent by construction: a stale checkout looks exactly like
a quiet one. Two levels close that, and they are one mechanism, not two:

| Level | Carrier | Covers |
|---|---|---|
| 1 | `helpers/shared-memory-check.sh`, called by `session-bootup.sh` | the gap **between** sessions — reports what arrived since this instance last looked |
| 2 | `scripts/shared-memory-watch.sh`, driven by `Monitor` | the time **inside** a running session — reports each new commit as it lands |

Both share ONE cursor (`config/shared-memory-state.json` in the instance), so they
never double-report, and nothing falls between them.

**Watching more than shared memory** (PRs, comments, merges, parallel sessions)? Use skill
`collab-watch`: its `scripts/collab-watch.sh` arms this watcher together with the others
(own cursor and lock under `COLLAB_WATCH_STATE`) — do not arm both.

## When to arm, unasked

1. **Right after your own push that expects a reaction** — a question to another
   instance or person, an open point for counter-checking, a preflight someone has to
   answer. Arm in the SAME turn; an expected external trigger gets watched, never
   waited for. **Carried by `helpers/watch-gate.cjs`** (Stop hook): a turn that pushed an
   entry from this instance to another party (not `status: info`/`done`/...) and ends
   with no live watcher is blocked once. Measured before the gate: 33 of 63 pushes on one
   instance had no watcher; the prose alone never fired. A pure report that awaits
   nothing carries `status: info`.
2. **Once at the beginning of a session that works with shared memory** or
   cross-instance coordination. Not in every arbitrary session — that would be
   constant load without an occasion.

## How to arm

```
Monitor({ command: "bash core/scripts/shared-memory-watch.sh watch 300",
          description: "new commits in the shared-memory repo from other instances",
          persistent: true })
```

`persistent: true` on purpose — the same shape as a PR org-watch. The first version of
this script exited on the first find, which made every find a re-arm ritual and left
the window between exit and next arm unwatched while looking armed. It now reports one
line per find and keeps running; it ends with `TaskStop`, with the session — **or when the
Monitor expires**: measured 2026-10-09 on the Windows instance (Claude Code 2.1.295), the Monitor tool announced
"expires in 30m" despite `persistent: true`, delivered the expiry notice after 30 minutes and
the watcher process was gone at the next look (`status`: "not armed"). Re-arm on the expiry
notice while the session still waits on someone; `helpers/watch-gate.cjs` blocks a turn that
expects a reaction with no live watcher, so a missed re-arm surfaces at the next stop.

Paths are overridable (`SHARED_MEMORY_REPO`, `SHARED_MEMORY_STATE`,
`SHARED_MEMORY_LOCK_DIR`) — the instance decides where its shared repo is cloned; the
core never hardcodes an instance path.

## What the script guarantees

- **One watcher per machine.** The lock in `.claude-state/` stops three parallel
  sessions from hammering the same fetch and all reacting to the same commit. A second
  arm says so and exits instead of doubling.
- **Your own pushes are not events — but what your pull brought along is.** Never the
  git author name: one operator's name is identical on their Mac and their Windows
  workstation, so a name filter would swallow the other own instance, which is exactly
  the signal wanted. A new head reachable from the local checkout is NOT proof of
  "ours" either: the pull before an own push carries every foreign commit pushed in
  between (measured 2026-09-30 — a request to this instance was skipped that way). For
  such a range the watcher asks the inbox reader, which drops the own entries by
  `SHARED_MEMORY_SELF`, and reports whatever is left.
- **A missing cursor is a loud abort, never a silent idle.** Watching blind and
  watching nothing look the same from outside; the script refuses instead.
- **Missed windows still surface.** The cursor is a file and only advances on a
  reported find, so anything pushed while nothing watched is a find at the next poll.

## Proof it fires

`scripts/shared-memory-watch-test.sh` runs the watcher against a sandbox repo (bare
remote plus two checkouts, no network, no real data), lets the "colleague" push twice,
and asserts BOTH that the first find is reported and that the second still comes. A
watcher nobody has ever seen fire cannot be distinguished from a broken one — run this
after touching the script, and when installing on a new machine.

## After a find

The script reports only THAT and WHAT (count, authors, files) — no judgement. Read the
diff, place it (does it answer an open question of ours? pure info? does it need an
answer?), then act normally. Reading and checking inside your own system is free;
writing back into the shared repo is visible to every collaborator and follows the
same care as any other entry there — leak discipline, format, push when done.

## Limits, deliberately

- **No headless/scheduler path.** When the session ends, the poll ends. A 24/7 daemon
  would be a separate decision with its own cost.
- **No auto-answering on suspicion.** The skill detects and reports; what gets answered
  is decided by the session that receives the notification.

## Housekeeping

```
bash core/scripts/shared-memory-watch.sh status    # armed: pid N | not armed
bash core/scripts/shared-memory-watch.sh disarm    # clear a stale lock after a kill
bash core/scripts/shared-memory-watch-test.sh      # negative control
```

After a `TaskStop` the lock can survive (the monitor kills the process, the trap does
not always run) — `disarm` before arming again, otherwise the script reports "already
armed" and does nothing.
