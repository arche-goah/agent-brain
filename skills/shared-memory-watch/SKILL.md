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

## When to arm, unasked

1. **Right after your own push that expects a reaction** — a question to another
   instance or person, an open point for counter-checking, a preflight someone has to
   answer. Arm in the SAME turn; an expected external trigger gets watched, never
   waited for.
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
line per find and keeps running; it ends with `TaskStop` or with the session.

Paths are overridable (`SHARED_MEMORY_REPO`, `SHARED_MEMORY_STATE`,
`SHARED_MEMORY_LOCK_DIR`) — the instance decides where its shared repo is cloned; the
core never hardcodes an instance path.

## What the script guarantees

- **One watcher per machine.** The lock in `.claude-state/` stops three parallel
  sessions from hammering the same fetch and all reacting to the same commit. A second
  arm says so and exits instead of doubling.
- **Your own pushes are not events.** The discriminator is reachability from the local
  checkout, not the author name — one operator's name is identical on their Mac and
  their Windows workstation, so a name filter would swallow the other own instance,
  which is exactly the signal wanted.
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
