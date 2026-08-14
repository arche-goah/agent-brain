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
   - If anything came up in `docs/maintenance/brain-scan-auftraege.md` or project order
     lists: update the entries.
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
4. **Commit gate (operator order 2026-08-01 — mandatory, replaces the old "only on request"):**
   - Check `git status`. Commit all commit-ready material (meaningful commit
     message naming the session content).
   - **Push gate, precised 2026-08-13 (operator order; supersedes the 2026-08-04
     wording that gated every `main` push):** the deciding line is WHOSE state a push
     changes, not the branch name.
     * **The instance's OWN private brain repo: `main` push is free** — close commits,
       memory snapshots, instance docs change nobody else's state. Verify visibility
       once per session when in doubt: `gh repo view --json visibility` (a repo that
       is not private strips this freedom).
     * **Every SHARED repo of the ecosystem — core, marketplace, suites — keeps the
       gate even while private:** feature-branch push is free (it is the technical
       precondition of the PR), merge and release run through the PR pipeline or an
       explicit operator OK.
     * **Public repos, switching anything public, deployments: always gated.**
     The gate is the agreement itself — whether a mechanical ask-prompt exists besides
     it is the instance's business (some deliberately have none; a missing prompt is
     NOT an approval).
   - Name whatever is NOT committed explicitly in the close report WITH a reason
     (e.g. secrets/.env, half-finished state that must be discussed with the operator
     first, deliberately local experiment). "Forgot" is not a valid reason — the
     2026-08-01 incident (70 files uncommitted after close) must not happen again.
   - Then a quick check: `.claude/HANDOFF.md` fresh (timestamp), `docs/memory-snapshot/`
     export ran (memory-sync output), working tree clean or the remainder justified.
5. **Close report to the operator:** 3-5 lines — what was persisted, what stays open
   (with its location), then explicitly: "Persisted — you can shut down." Only after
   this report is the session closed.

## Scope

- Committing applies IN GENERAL (operator order 2026-08-01): commit commit-ready
  material — allowed continuously, MANDATORY at close (step 4 = verification point);
  name non-commit-ready material WITH a reason. Push rule as in step 4 (2026-08-13):
  own private brain repo free, shared ecosystem repos gated even while private,
  public/deploy always gated; feature-branch push free.
- **The commit/push policy must not live here alone.** This skill only loads at session
  end — a session that ends in a hard kill or a topic change never had it in context
  (incident "70 files uncommitted"). The instance therefore carries it as a base rule
  in `.claude/rules/feedback.md` (always loaded); this step 4 is the **verification
  point**, not the source.
- The SessionEnd hook still runs on the real exit anyway (idempotent: HANDOFF is
  overwritten; the session log dedupes identical lines in the script itself).
