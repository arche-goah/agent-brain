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

Both share ONE cursor (`.claude-state/shared-memory-state.json` in the instance — runtime state, untracked; an old `config/` cursor is taken over once), so they
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
Monitor({ command: "bash core/scripts/shared-memory-watch.sh watch 60",
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

**The poll interval must be a small fraction of the shortest expiry ever seen** (measured
2026-10-11, same instance, Claude Code 2.1.296: the Monitor announced "expires in 5m", not 30m —
the expiry is the harness's and changes between versions). With the old default of 300 s an
arm polled ONCE before it expired, and a reply pushed a minute after the arm waited a full
re-arm cycle. The default is 60 s; never copy a longer number from an older note, and when the
announced expiry shrinks again, shrink the interval with it.

Paths are overridable (`SHARED_MEMORY_REPO`, `SHARED_MEMORY_STATE`,
`SHARED_MEMORY_LOCK_DIR`) — the instance decides where its shared repo is cloned; the
core never hardcodes an instance path.

## Silent arm — for an operator who must not be interrupted

Every Monitor event starts a new agent turn, and that turn prints text and tool lines
into the terminal while the operator is still reading the previous answer. The harm is
the output itself, not its content. When the instance's rules say "no interruption
while the operator reads or writes" (an instance rule, not a core default), arm the
watcher SILENT: the script's stdout goes into a queue file, nothing reaches the
Monitor's stdout, so no event wakes the agent.

```
Monitor({ command: "bash core/scripts/shared-memory-watch.sh watch 60 >> <queue-file> 2>&1",
          description: "silent shared-memory watcher, finds go to the queue file",
          timeout_ms: <the longest the harness allows> })
```

- **Queue file location is a measurement, not a guess.** An instance may deny the
  agent access to its state directory (`.claude-state/**`); then a redirect there is
  refused by the harness and the Monitor never starts. Use a path the agent may write
  and read — the session scratchpad suits a watcher, because both end with the session.
- **The queue is read at a point boundary** — when the current point is finished or
  the operator asks for the queue — never in between. A find is a queue entry, not an
  interruption.
- **Arm silent right after the push, in the same turn.** The watch gate that demands a
  watcher after a push is satisfied by a silent one; "no watcher at all" is not the way
  to avoid interrupting.
- **Before re-arming (expiry, a restart): `disarm` first.** `TaskStop` leaves the lock
  behind; an arm onto a stale lock exits at once with "already armed" and the Monitor
  ends with exit 0 and no output — silent and dead, indistinguishable from a quiet
  watch. After arming, `status` must say `armed`.

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

**A request to this instance under a standing approval is handled, not asked.** The class
list lives in `.claude/rules/open-items-standing.json` (the same file the session-start list
reads, `rules/intelligence.md`). A find that is a request addressed to this instance and
matches a class there is worked and answered in the same session, then reported — the
mid-session twin of the session-start rule. Measured 2026-10-16: the standing class only
fired at the next session start, so a request that arrived while the session ran waited
for the operator's go although he had given it for good. Check the match with
`python3 core/scripts/open-items.py --owner <owner>` (the item prints as `standing`).

## Limits, deliberately

- **No headless/scheduler path.** When the session ends, the poll ends. A 24/7 daemon
  would be a separate decision with its own cost.
- **No auto-answering on suspicion.** The skill detects and reports; what gets answered
  is decided by the session that receives the notification — by the standing classes
  above where the operator declared them, otherwise case by case.

## Housekeeping

```
bash core/scripts/shared-memory-watch.sh status    # armed: pid N | not armed
bash core/scripts/shared-memory-watch.sh disarm    # clear a stale lock after a kill
bash core/scripts/shared-memory-watch-test.sh      # negative control
```

After a `TaskStop` the lock can survive (the monitor kills the process, the trap does
not always run) — `disarm` before arming again, otherwise the script reports "already
armed" and does nothing.
