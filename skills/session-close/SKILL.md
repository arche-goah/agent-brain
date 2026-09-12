---
name: session-close
description: Close a session cleanly — persist open work to memory, write handoff + session log, run the memory export, then give the explicit release "you can shut down". Use when the operator says "session abschliessen", "beende die session", "session beenden", "ich fahre jetzt (dann) alles runter", "kann ich die session beenden?", "wir sind fertig fuer heute", "mach schluss", "shutdown" — or the English equivalents "close the session", "end the session", "I'm shutting everything down now", "can I end the session?", "we're done for today", "wrap it up". NOT on a mere topic change.
---

# Session Close (active shutdown)

The SessionEnd hook is best-effort only (it does not fire on a hard kill). This skill is the
reliable path: the operator triggers it IN the session, everything is persisted deliberately,
then an explicit release follows.

## Procedure (in this order)

1. **Secure open work (semantic — no script can do this):**
   - Write unfinished orders / intermediate states / decisions of this session as memory,
     or update existing memories (observe the auto-memory rules; maintain the MEMORY.md
     index). Do not store anything already finished a second time.
   - **Research leaves a carrier (2026-08-21):** if this session read a live system in
     bulk (reference showfile, device readouts, exports, doc sweeps), the FINDINGS get a
     file before the close — memory file (instance), ledger entry, suite reference
     (anything that holds on a foreign rig), or shared-memory. A summary line in the
     session log is an index, not a carrier; the next session would have to read live
     again. `core/helpers/recall-gate.cjs` asks this mechanically when wired; the
     answer "nothing reusable" is allowed, silence is not. Before the NEXT live read:
     `python3 core/scripts/transcript-recall.py <keyword>` (interpreter per instance rule).
   - If anything came up in `docs/maintenance/brain-scan-auftraege.md` or project order
     lists: update the entries.
   - **STANDING PROMISES — say per line whether the condition still holds (2026-09-12):**
     If `.claude-state/promises.jsonl` exists, read it and go through the promises made
     in this session. Each row carries the promise and what bound it. For every one:
     the condition still holds (it stays), or it has lapsed (it is over, and it says so
     in the close report). A promise whose condition is gone does not quietly become a
     standing rule, and it never outranks a step of this procedure.
     **The incident that forced this (collaborating instance, 2026-09-11):** permission
     for ONE unattended task, granted while the operator slept ("no commit, no push").
     The task ended, the operator was back in the chat, awake — and the promise was
     still being obeyed, so the mandatory commit step below was silently skipped and the
     close was reported as complete anyway. Nothing in the text marked the omission,
     which is why the check sits here and not in a hook.
     No file, or nothing open: one sentence, move on. `core/helpers/promise-gate.cjs`
     writes the rows when wired; its absence does not excuse the question.
   - **MANDATORY GATE for live states (rig/desk/show) — tightened 2026-08-02 (operator order):**
     If the session CHANGED a live system, its state is **measured**, not copied from
     one's own docs. **WHICH verify path that is, is instance knowledge** and lives in
     the instance rules file (`.claude/rules/working-rules-instance.md`) — device, desk
     and tool names belong there, never in this shared artifact
     (CONVENTIONS.md §1: "No behaviour that only makes sense for one owner's rig").
     The result (green, or findings) goes into the close report AND the session log. A
     read-only check is NOT a "new live action" — the ban below targets rebuilds,
     not measuring. **If no verify path exists for the touched system, that is a
     REPORTING EVENT** (mechanism discipline) — no improvised substitute path, no
     silent omission.
     ⚠ **INCIDENT 2026-08-01 that forced this gate:** The session changed a live
     network port's VLAN assignment. Both **full-audit AND session-close** ran that
     day — the live system was still never measured, because `full-audit` explicitly
     excludes live systems and session-close only demanded the "documented state".
     Result: a live port label contradicting the actual VLAN config stood for a day,
     although the instance's own naming check reports exactly that immediately. The
     operator found it on 2026-08-02, not the process. Lesson: "an audit ran" does
     NOT mean "the live system was checked".
   - **CROSS-INSTANCE GATE — if this setup shares memory with other instances or people
     (operator order 2026-08-17):** ask, per finding of this session, whether its REACH
     goes past this machine — a measurement someone else's work depends on, a correction
     that retires something the shared record still claims, a decision another instance
     must follow. If yes, it belongs in the shared record BEFORE the session ends, and
     the entry gets pushed, not left staged. Where that record lives and what the entry
     format is, is instance knowledge (instance rules file) — this artifact only demands
     that the question is asked.
     **The trap this closes:** a PR thread, a chat answer and a merged commit all FEEL
     like the finding is recorded. They are the volatile forms; the collaborator on the
     other machine reads none of them at session start. Measured 2026-08-17: three merged
     PRs corrected a claim the shared record still stated as open, and the shared entry
     had to be written after the operator asked — the close ran without it.
     **"If needed" is a filter, not an excuse to skip:** most sessions have nothing with
     that reach, and then this step is one sentence in the close report. A session that
     changed a SHARED tool, corrected a SHARED claim, or answered another instance's
     question almost always has something.
   - After this: no further live CHANGES (measuring stays allowed).
2. **Mechanical close:**
   ```bash
   bash "$CLAUDE_PROJECT_DIR"/core/helpers/session-closing.sh
   ```
   ```bash
   node "$CLAUDE_PROJECT_DIR"/core/helpers/memory-sync.cjs export
   ```
3. **Session log, semantic + decision log (since 2026-07-31, AFTER step 2):**
   - Append a short entry to `docs/maintenance/session-log.md`: 2-4 indented lines
     directly below the mechanical line from step 2 — the session's topic, decisions
     taken with pointers to doc/commit/memory, open ends. No prose protocol — index
     lines that point to the places where the reasoning is documented.
   - **Pillar check:** Did the session produce a fundamental/architecture decision
     (shapes future work, expensive to reverse, or explicitly set as a guardrail by
     the operator)? Then add an entry to `docs/maintenance/decision-log.md` (format in
     its header) — incl. rejected alternatives + co-dependencies. Domain decisions
     (e.g. in a network or show domain) still go FIRST into the domain's change log;
     the decision log then only links there instead of duplicating.
4. **Commit/push gate — this step VERIFIES the instance's rule, it does not set one.**
   The wording that used to stand here cached ONE instance's dated policy, and a cached
   policy goes stale silently — which is the drift the Rule-Conflict Protocol's
   back-propagation step exists to catch. So this step names no policy of its own:
   - Read the instance's commit/push rule (`.claude/rules/feedback.md` or the
     instance's equivalent) and apply it. What it allows without asking, do; what it
     gates, list — with the proposed commit message — and ask.
   - **If the instance has no written rule, ask before committing or pushing.**
     "Close the session" is not by itself a go-ahead; a closing instruction that
     already includes it ("commit and close") is.
   - Feature-branch pushes toward an open PR are the technical precondition of review,
     not a merge or release, and count as allowed unless the instance says otherwise.
   - Name whatever stays uncommitted in the close report WITH a reason (secrets/.env,
     half-finished state, a deliberately local experiment, or simply "no go-ahead").
     "Forgot" is not a reason — the 2026-08-01 incident (70 files uncommitted after
     close) must not happen again; asking and getting a "not now" is a fine outcome,
     silently forgetting is not.
   - Then a quick check: `.claude/HANDOFF.md` fresh (timestamp), `docs/memory-snapshot/`
     export ran (memory-sync output), working tree clean or the remainder justified.
5. **Close report to the operator:** 3-5 lines — what was persisted, what stays open
   (with its location), then explicitly: "Persisted — you can shut down." Only after
   this report is the session closed. If the setup shares memory across instances, the
   report says which findings went there **or that none had that reach** — an unstated
   cross-instance step reads as done and is the one nobody can check afterwards.

## Scope

- The commit/push policy is INSTANCE knowledge and lives in the instance's rule file.
  This skill applies it at close and carries no copy of it — instances differ (one
  brain commits continuously and pushes its own private `main` freely, another gates
  every commit), and whichever wording stood here would be wrong for the others.
- **The commit/push policy must not live here alone.** This skill only loads at session
  end — a session that ends in a hard kill or a topic change never had it in context
  (incident "70 files uncommitted"). The instance therefore carries it as a base rule
  in `.claude/rules/feedback.md` (always loaded); this step 4 is the **verification
  point**, not the source.
- The SessionEnd hook still runs on the real exit anyway (idempotent: HANDOFF is
  overwritten; the session log dedupes identical lines in the script itself).
