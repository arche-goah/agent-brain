- **Every brain can tell what needs the operator, and the session start says when it cannot.** (test: T1)

  **Operator decision 2026-10-16:** only what really needs the operator goes to the operator. What can be settled cleanly alone or between the AIs, is reversible and documented, the AI decides without asking — assured in every core.

  **The gap, measured the same day on a collaborator's brain:**
  - its core predated ASK OR ACT;
  - three core rules point at "the instance's operator-only list", and the template shipped none;
  - every commit and push raised a permission dialog;
  - the human's answer to that was `Bash(*)`, which switches every check off.

  **New:**
  - `templates/rules-instance/operator-only.json`: the one list, generic labels, and a comment that it is read in both directions. `bootstrap-brain.sh` copies it.
  - `scripts/decision-readiness.py`, run by the session start after watch readiness. It names:
    - rule files not imported by `CLAUDE.md` (an `@` inside a code fence does not count);
    - a core in use that predates ASK OR ACT;
    - a missing or empty list;
    - an `ask` rule that catches an everyday commit, push or PR comment (matched with Claude Code's rule semantics, so a targeted `git push * main*` is no finding);
    - `Bash(*)` in `allow`.

    It is silent when the brain is fine, read-only, with no network.
  - `rules/working-rules.md` ASK OR ACT: the list's path, the two-direction reading, and the carrier.

  Fixture `test-decision-readiness.sh`: not a brain silent · old core, missing list and everyday dialog named, a settings edit under ask no finding · `Bash(*)` named, empty ask no dialog finding · rules not imported named · ready brain silent · empty list named. Live on the macOS instance: silent.
