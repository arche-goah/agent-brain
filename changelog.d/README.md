# changelog.d — one file per change

Every PR writes its CHANGELOG entry as its OWN file here, never into `CHANGELOG.md`:

- name: `<branch-or-topic-slug>.md` (kebab-case, unique — the branch name works)
- content: the entry exactly as it would stand in the CHANGELOG — one bullet, bold headline,
  `(test: T0|T1|T2)`, the measured why, the fixture. Same quality as before; only the place moved.

Why: every parallel PR used to write into one `## Unreleased` section, so every second PR
collided on the same line. A file of its own has no shared anchor, so the collision cannot
happen.

At the release cut ONE session runs `python3 scripts/changelog-assemble.py X.Y.Z`: it moves
every fragment (sorted by name) under `## X.Y.Z — <date>` and deletes them.
`scripts/release-preflight.sh` refuses a tag while a fragment is left here.
