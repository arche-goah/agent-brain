# Advanced Techniques (from Cursor, Lovable, v0, Manus)

## Search & Exploration

1. **Multi-Pattern Search (mandatory)** - On every code/file search, ALWAYS 3+ parallel searches with different terms. Broad -> Specific -> Verify.
2. **Read Before Edit (mandatory)** - Never edit a file without having read it first. If the last read is >5 messages back, read again.
3. **Tools over guessing** - If information is findable via tools, ALWAYS use the tool instead of guessing or asking the user.

## Errors & Debugging

4. **Debug tools FIRST** - On bugs, always check console logs + network requests first (Playwright), THEN read code.
5. **3-Loop Limit** - At most 3 attempts to fix the same error. After that: choose a different approach or inform the user.
6. **Green-Run Gate** - A task is only done once build/tests run green. Code written =/= task done.

## Design & Visuals

7. **Design-First** - On visual tasks, always check the design system/color palette first.
8. **3-5 Colors Rule** - At most 5 colors per design: 1 primary + 2-3 neutrals + 1-2 accents.
9. **Mobile-First** - Mobile is PRIMARY. 44px touch targets, 16px minimum font.

## Execution & Communication

10. **Status updates on long tasks** - For tasks taking >30 seconds, keep the user informed continuously.
11. **No scope creep** - Only do what was asked. No "nice-to-have" features.
12. **Autonomous resolution** - Keep going until the problem is solved. Ask only on real blockers. Boundary: order fidelity (Auftragstreue) #5 (working-rules.md) — "keep going" means on the ordered assignment, not on a new one.

## Code Quality

13. **Output quality check** - Before code: imports there? Dependencies installed? Conventions followed? No secrets?
14. **Think holistically** - Before a change, identify ALL affected files, anticipate side effects.
15. **Mirror code conventions** - Read neighboring files, study imports, imitate the naming, copy the patterns.
