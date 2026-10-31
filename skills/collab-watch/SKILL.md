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
4. **Always, from the first reply of a session, when `.claude/rules/collab-watch.json` is filled in** —
   the standing watch (operator order 2026-10-16: a machine without it saw incoming PRs and requests only
   at the next start and answered nothing). Re-arm at every expiry notice. Carried by
   `core/helpers/watch-gate.cjs` case (g); a brain that must not watch declares
   `"standing_watch": "off: <why>"` in that file. What the watch reports on the instance's own
   terrain is handled in the same turn — measure, check, merge or answer with who/when; the
   "shall I?" question exists once, at session start, for the open points listed there.

## How to arm

Precondition: the instance file `.claude/rules/collab-watch.json` (copy
`core/templates/rules-instance/collab-watch.json`, fill every placeholder). Repos,
intervals and parties are THERE, never in a rule or a prompt.

```
Monitor({ command: "bash core/scripts/collab-watch.sh",
          description: "collaboration watch: PRs, merges, comments, shared memory, sessions",
          timeout_ms: 1800000 })
```

- `bash core/scripts/collab-watch.sh --dry-run` prints the plan without arming.
- **Cadence is conversation speed.** A reply waits up to one interval on each side; the
  template polls shared memory every 30 s and the core repos every 60 s (300 s meant up to
  ten minutes per question and answer between two AIs). An existing instance file keeps its
  old numbers — lower them there. Every own machine polls under one account; the repo watch
  prints `NOTE: GitHub budget …` and slows itself below `WATCH_RATE_FLOOR_PCT` (default 25)
  of the API budget, and says so again when it is back.
- **Scope** `COLLAB_WATCH_SCOPE=all` (default) · `peers` · `<party>`. Anything but `all`
  drops events for good (cursors advance before the filter). **Before arming a filtered
  scope, count the same window unfiltered once** — unfiltered n>0 and filtered 0 means
  the filter is suspect, not the world quiet.
- **A session that owns a topic arms it too:** `COLLAB_WATCH_TOPICS="<topic> …"` next to a
  party scope. A repo watch whose tag is a topic, and a shared-memory find in a `<topic>/`
  folder, then pass from EVERY party — the operator's other machine included. Without it a
  one-collaborator scope drops the other own machine's PRs in the very repo the session owns
  (measured 2026-10-11).
- **Leaving an item to another session is a hand-over, delivered to THAT session.** When
  several sessions on one machine split the work by topic, an item one of them declines goes
  to the session that owns the topic (session message, or a shared-memory note in its topic
  folder its watch reports) — never only back to the sender ("ask the other session"). An
  answer to the sender alone reaches nobody who acts: measured 2026-10-11, three points of the
  operator's other machine lay unworked for hours this way until the operator asked.
- **Never add an author filter on the operator's login.** All own machines push under one
  account; the filter would swallow the other own machine — the very signal wanted.
- **"already armed"** names a live PID, not a session. Check `ps` and its parent chain
  before telling anyone another session exists. Two sessions that must both watch:
  each sets its own `COLLAB_WATCH_STATE` (moves cursors AND locks).

## Reading an event

| Line | First move |
|---|---|
| `COMMENT`, `PR`, `MERGED` | open it; handle below |
| `CI-RED <repo> <workflow> on <branch> (<event>, <conclusion>) <url>` | a run went red on a watched repo (also `cancelled`: a job that never got a runner ends that way). Open the run; a PR of ours or main: fix or re-run (`gh run rerun <id> --failed`) in the same turn and arm `ci-watch.sh` on it. This line is the net UNDER the per-push ci-watch (working rule #9), not a replacement for arming one |
| `... branch is LOCAL in this machine's clone` | made on THIS machine — this session (check your own PRs first), a parallel session or a hand checkout; not a collaborator, not the other own machine |
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
   hardware or tools you also own: re-measure on your own (skill `pr-live-verify` takes
   over this step). A live-behaviour row without its measurement state (date · machine ·
   method, `rules/thinking-protocol.md` evidence chain) gets the question for that state
   as the FIRST review comment — no merge on plausibility; where the suite opted in,
   `scripts/live-doc-lint.py --changed <base>` names such rows. A counter-check "OK on this OS" of a core PR has two
   halves (operator decision 2026-10-26): CI runs every fixture suite on ubuntu, macOS and
   Windows (job `portability`), and the check waits for it green (`ci-watch.sh`, exit 0) —
   that half replaced the full local run, which took 12-22 min per PR and machine and repeated
   what CI does; the other half runs on the real machine what CI cannot see: the suites of the
   touched parts and, where the PR claims behaviour on a live system, that system. Name both
   result lines. `bash scripts/ci-lint-local.sh` stays the tool for a push without a CI round
   trip, not part of the check (it was, after the touched fixtures alone missed a CI lint step
   twice on 2026-10-21 — the CI watch catches that now).
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
4. **Merge when both sides said yes — whoever comes first** (operator decision 2026-10-11:
   a ready PR that waits for one particular person "hangs for nothing"). Shared work is
   merged by whichever party gets to it first, once ALL of these hold: the author reported
   it done (or verified it live), the other side reviewed it OK, CI is green, the repo's
   conventions are met, and the reviewed commit IS the head. Leave a one-line comment in
   the PR saying who merged and on which two OKs. Exceptions are the instance's merge rules
   (a jointly owned core: its maintainers merge after the counter-check); releases (tag,
   pin) stay with the repo's owner. Never with own open findings, never over a request in
   the PR body addressed to this machine ("please counter-check on macOS") that no comment
   of this instance answered — `helpers/merge-request-gate.cjs` holds the merge. Merge
   with `--match-head-commit <reviewed sha>` in the repo's style (merge vs. squash).
   "CI green" speaks about code, never about whether the author is done.
   **A refused merge is a decision, not an obstacle:** when the permission layer refuses
   `gh pr merge`, do NOT re-issue it as `gh api -X PUT …/pulls/<nr>/merge` or any other
   form — that launders the refusal. Report it and get the operator's word (an earlier
   version of this step named the API call as a "second legitimate form"; corrected
   2026-10-09, coherence register of the proving brain). The general rule — no refused
   action in another form, tool or session — is `rules/working-rules.md`, "A refusal is a
   decision"; `mechanism-guard` blocks the API merge through the core's `mechanism-rules.json`.
   Merge traps, each measured:
   - `--match-head-commit` needs the FULL 40-character sha — a short sha is rejected by
     the API ("Could not coerce value … to GitObjectID"), measured 2026-10-09.
   - `gh pr merge --auto` merges IMMEDIATELY in a repo whose branch protection requires
     no checks — never use it as "merge when green"; run `scripts/ci-watch.sh` first.
   - Stacked PRs: merging the base with `--delete-branch` closes every PR stacked on it.
     Retarget the child to `main` (`gh pr edit <child> --base main`) BEFORE deleting.
   - A candidate/integration branch merged as one squash: list every contained PR as
     "(#n)" in the squash body — `pending-clauses.py` finds a PR in the pin by that text,
     and without it a merged PR reads as "not provably in the pin".
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

**Never wait on a prompt.** A permission prompt halts the whole session until the operator
clicks — every channel goes blind behind it (measured 2026-10-18: one merge prompt stopped
an armed watch until the operator came back). While armed, issue only what passes without a
prompt. An action that may raise one — not surely covered by the allow list, or prompted or
refused before in this session (a merge, deleting a branch, a settings change) — is not
issued: it goes, with every question for the operator, into the instance's ledger, and the
operator gets them bundled in the next report. The rest of the work continues: whatever is
safely doable gets done, whatever the agent can decide as well as the operator (comparative
test, `rules/intelligence.md`) gets decided, and only what MUST be the operator's decision
is parked and listed later. No duration is needed — the watch runs until the operator
stops it. Allowed
actions must go through; a prompt on one is a finding about the allow list, not a reason to
stop the watch. This holds ONLY in autonomous mode (next paragraph); outside it the operator
gets the interactive question with clear options as always.
**One trigger for both halves** (operator decision 2026-10-27, replaces the split of
2026-10-19): parking ACTIONS that may raise a permission prompt, and parking the operator's
DECISIONS, both hold only in autonomous mode, which the operator orders in words
(`autonomous-run`, hard gate 7, `helpers/autonomous-mode.cjs`). A standing watch alone is not
that mode: it is armed from the first reply in every session (watch-gate case g), so parking
actions whenever it is armed parked every prompting step of every interactive session too —
the operator at hand then never saw the prompt they were there to answer. With the operator
at hand, a prompting action is issued and a real decision is asked through the question tool.

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
Every Monitor expires: its `timeout_ms` (read the live tool schema — on Claude Code 2.1.303,
measured 2026-10-19, it is a required field, default 5 minutes, capped at 30 minutes, and the
older `persistent` flag no longer exists) — set it to the cap and re-arm on the expiry
notice; `helpers/watch-gate.cjs` catches a turn that awaits a reaction with no live watcher.

After a `TaskStop` a lock can survive (the trap does not always run); a lock whose PID is
dead is reclaimed automatically on the next arm.
