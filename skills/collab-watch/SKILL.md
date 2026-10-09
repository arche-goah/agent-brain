---
name: collab-watch
description: Watch every collaboration channel at once (new PRs, merges, comments incl. on merged PRs, review comments, shared-memory pushes, parallel sessions joining this repo) and handle what arrives autonomously - review with evidence chain, comment, merge by ownership rules, follow-up PRs. One Monitor call arms it. Use when the operator says watchdog, monitor, watch, PR-watch, "keep an eye on", "a PR is coming", "handle PRs on your own", "what's new from <X>", or German "beobachten", "ueberwachen", "im Auge behalten", "watchdog einrichten", "autonom abhandeln", "bearbeite PRs eigenstaendig", "was gibt es Neues von <X>", "kommt gleich ein PR"; also unasked when a session works on collaborator contributions. NOT for looking at one PR once (use a review) and NOT for shared-memory alone (shared-memory-watch).
---

# Collaboration watch + autonomous handling

A collaboration watch fails silently by construction: a watch that is dead, filtered wrong,
or polling the wrong channel prints exactly what a quiet day prints. Everything below exists
because one of those happened. The mechanisms carry the lessons; the reasons are in
[references/watch-lessons.md](references/watch-lessons.md).

## What it covers

| Channel | Carrier | Reports |
|---|---|---|
| repos | `scripts/repo-activity-watch.sh` | new PR · merge (by whom) · conversation comment · inline review comment — also on merged PRs |
| shared memory | `scripts/shared-memory-watch.sh` (skill `shared-memory-watch`) | commits from other instances/parties, with sender |
| parallel sessions | `scripts/parallel-sessions-watch.sh` on top of `scripts/parallel-sessions.sh` | a session joining or leaving this repo |
| one PR, closely | `scripts/watch-pr.sh <owner/repo> <nr>` | comments, review verdicts, merge/close (exits then) |

The first three are armed together by `scripts/collab-watch.sh`, each under
`scripts/watch-supervisor.sh` (a dying watcher prints `WATCHER-DIED`, then restarts).
A review verdict WITHOUT an inline comment is invisible repo-wide (GitHub has no such
endpoint) — follow a PR under review with `watch-pr.sh`.

## When to arm — unasked

1. The operator names a watch in any words (see description) — the words are the order;
   do not ask what is meant.
2. A PR is announced, or the session starts working on collaborator contributions.
3. Right after an own push that expects a reaction (question, counter-check request).

## How to arm

Precondition: the instance file `.claude/rules/collab-watch.json` (copy
`core/templates/rules-instance/collab-watch.json`, fill every placeholder). Repos,
intervals and parties are THERE, never in a rule or a prompt.

```
Monitor({ command: "bash core/scripts/collab-watch.sh",
          description: "collaboration watch: PRs, merges, comments, shared memory, sessions",
          persistent: true })
```

- `bash core/scripts/collab-watch.sh --dry-run` prints the plan without arming.
- **Scope** `COLLAB_WATCH_SCOPE=all` (default) · `peers` · `<party>`. Anything but `all`
  drops events for good (cursors advance before the filter). **Before arming a filtered
  scope, count the same window unfiltered once** — unfiltered n>0 and filtered 0 means
  the filter is suspect, not the world quiet.
- **Never add an author filter on the operator's login.** All own machines push under one
  account; the filter would swallow the other own machine — the very signal wanted.
- **"already armed"** names a live PID, not a session. Check `ps` and its parent chain
  before telling anyone another session exists. Two sessions that must both watch:
  each sets its own `COLLAB_WATCH_STATE` (moves cursors AND locks).

## Reading an event

| Line | First move |
|---|---|
| `COMMENT`, `PR`, `MERGED` | open it; handle below |
| `... branch is LOCAL in this machine's clone` | made on THIS machine (parallel session or hand checkout) — not a collaborator, not the other own machine |
| event under the operator's own account | run `scripts/parallel-sessions.sh` and check local branches BEFORE saying "the other machine" or "foreign" |
| `FOUND: n new commit(s)` with n>1 | read `git log` of the range for the parties before naming one |
| `SESSIONS: changed` | own-account work may now come from that session; a PR of a parallel session is handled by its author session |
| `WATCHER-DIED` / `WATCH-ERROR` | the watch is blind for that channel — say so, fix or re-arm |

## Autonomous handling — the DEFAULT once armed

Arming IS the order. Observation mode ("only report", "do not merge") is the explicit
opt-out and holds for that session only.

1. **Review with evidence chain.** Read diff, PR text and the WHOLE thread (comments carry
   the history, not only `reviews`). Split every claim: measured / derived / assumed. Take
   open measurements yourself when this machine can. A PR that claims live behaviour of
   hardware or tools you also own: re-measure on your own (an instance skill for this, if
   it has one, takes over this step).
2. **Findings go on the PR** (`gh pr comment`): values with date, sources with URL. The
   thread is the shared memory of the collaborating brains.
3. **Measure CI, do not read it off:** `Monitor` on
   `bash core/scripts/ci-watch.sh pr <owner/repo> <nr> [timeout_s]` — never an own poll
   loop on `gh pr checks` (it exits 8 while checks run; an `|| continue` swallows that and
   the loop spins silently into its timeout). Exit 0 = green, 1 = red, **2 = NOT
   measurable, which is not green**: no run yet, no run coming (spending limit, Actions
   off, workflow filter), or — most often — a merge CONFLICT, for which GitHub builds no
   merge ref and starts no run. Separate them with one look:
   `gh pr view <nr> --json mergeable` (`CONFLICTING` = rebase, not "CI broken"); an empty
   `gh run list --branch <branch>` plus an empty check rollup = CI is not firing, a report
   event for the operator. A second branch as a control comes BEFORE any outage diagnosis.
4. **Merge by ownership — the instance's merge rules decide**, typically: a repo with one
   responsible owner → that owner merges; a jointly owned core → the maintainers merge
   after a counter-check; otherwise the author merges. Never with own open findings. Merge
   with `--match-head-commit <reviewed sha>` in the repo's style (merge vs. squash);
   `gh api -X PUT repos/<o>/<r>/pulls/<nr>/merge` is the second legitimate form when the
   permission layer refuses `gh pr merge` — if both are refused, retry later, never work
   around it. "CI green" speaks about code, never about whether the author is done.
5. **Own findings = follow-up PR, never a direct push to main.** Before any commit to a
   public repo: its leak scan, 0 findings.
6. **Write back:** statements in the instance (rules, memory) that the merged PR refutes are
   corrected in the same move.

**Park boundary:** an open question is NOT a reason to park while a collaborator can decide
it with you — the PR thread and shared memory are working channels, not a waiting room.
Park only what no agreement between the parties can decide: the operator's goals, money,
hardware, risk, external effect. **Hard limits, also in autonomous mode:** a part the PR
marks as a direction decision goes to the operator (the rest continues); tags, releases
and pins follow the instance's release rules; making repos public and deployments are
always gated.

## Local cross-session hand-off

Several sessions can share one machine and one checkout. What exists today:
`scripts/parallel-sessions.sh` (who is here; exit 2 = unknown, never "alone"), the
`SESSIONS` channel above, and the collision rules from AGENTS.md §8 — commit after every
block, never force-push a shared remote, hand work over through a note (memory or a PR
comment) instead of state left in the tree, one session assigns version numbers. Whether
the harness's agent messaging reaches ANOTHER local session is not measured in this core;
treat it as unavailable until a measurement says otherwise.

## Proof it fires

`scripts/test-repo-activity-watch.sh` (fake `gh`: every channel reports, nothing repeats,
an author filter and a shared cursor each turn a must-report case red),
`scripts/test-collab-watch-plan.sh` (scopes both ways, config rules),
`scripts/test-watch-supervisor.sh` (death announced, silence when healthy, child dies with
its supervisor), `scripts/test-watch-pr.sh`, `scripts/shared-memory-watch-test.sh`.
Run them after touching any watcher and when installing on a new machine.

## Housekeeping

```
bash core/scripts/repo-activity-watch.sh status|disarm      # with REPO_ACTIVITY_TAG/STATE_DIR set
bash core/scripts/shared-memory-watch.sh status|disarm      # with SHARED_MEMORY_LOCK_DIR set
```
After a `TaskStop` a lock can survive (the trap does not always run); a lock whose PID is
dead is reclaimed automatically on the next arm.
