#!/usr/bin/env python3
"""Two-sided fixture for the PLACEMENT + PROVENANCE checks of skill-lint.py.

Both directions, because only both of them together prove anything: a case that MUST
produce a finding, and a case that must stay SILENT. A linter that flags everything is
as broken as one that flags nothing, and the silent half is the one nobody writes.

Optional third and fourth property, when an OLD linter is passed as the second
argument (the review run, not the CI run): the same tree is linted with the unpatched
linter as a negative control — if the old one already reported these findings, the
patch would be decoration — and on a tree without drafts every PRE-EXISTING category
must come out identical old vs. new. That is the regression guard for the three places
the patch reaches into shared code (name-vs-directory, registry, findings dict).

Usage: skill-lint-placement-test.py [<skill-lint.py> [<old-skill-lint.py>]]
       (default linter: the sibling scripts/skill-lint.py)
Exit 0 = all properties hold.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

FM = "---\nname: {name}\ndescription: {desc}\n{extra}---\n\n# {name}\n\nbody\n"
HERE = Path(__file__).resolve().parent


def write_skill(d: Path, name: str, desc: str, extra: str = "") -> None:
    d.mkdir(parents=True, exist_ok=True)
    (d / "SKILL.md").write_text(FM.format(name=name, desc=desc, extra=extra),
                                encoding="utf-8")


def build(root: Path, with_drafts: bool) -> bool:
    """Returns whether the suite symlink could be created (Windows without developer
    mode refuses symlinks; that case is skipped, not failed)."""
    skills = root / ".claude" / "skills"
    skills.mkdir(parents=True)
    (root / ".claude" / "settings.json").write_text(
        json.dumps({"skillListingBudgetFraction": 0.04}), encoding="utf-8")

    names = []
    # A skill that lives in a suite is mounted as a symlink. Tool domain in the
    # description on purpose: placement must NOT fire on it.
    suite = root / "fake-suite" / "skills" / "suite-skill"
    write_skill(suite, "suite-skill", "Drive a grandma3 desk over osc.")
    try:
        (skills / "suite-skill").symlink_to(suite, target_is_directory=True)
        linked = True
        names.append("suite-skill")
    except OSError:
        linked = False

    # Predates the rule -> on the baseline -> silent even though it is local + domain.
    write_skill(skills / "legacy-rig-skill", "legacy-rig-skill",
                "Health sweep over the mikrotik rig.")
    # New, local, tool domain -> placement finding.
    write_skill(skills / "new-desk-helper", "new-desk-helper",
                "Store presets on the grandma3 desk.")
    # New, local, no domain, no provenance -> provenance finding.
    write_skill(skills / "new-plain-skill", "new-plain-skill",
                "Summarise a text file.")
    # New, local, no domain, WITH provenance -> silent. This is the negative control
    # for the provenance check: the field is the only difference to the line above.
    write_skill(skills / "good-new-skill", "good-new-skill",
                "Summarise a text file differently.",
                extra="provenance: step 1 measured 2026-08-22 by running it\n")
    # On the baseline AND already clean -> the baseline line has to go.
    write_skill(skills / "graduated-skill", "graduated-skill",
                "Rename files in a folder.",
                extra="provenance: step 1 measured 2026-08-22\n")

    names += ["legacy-rig-skill", "new-desk-helper", "new-plain-skill",
              "good-new-skill", "graduated-skill"]

    if with_drafts:
        # Correct draft -> silent, and deliberately NOT in REGISTRY.md.
        write_skill(skills / "_draft-good-draft", "good-draft",
                    "A prototype procedure.",
                    extra="status: draft\nprovenance: step 1 measured 2026-08-22\n")
        # Draft without either half -> two provenance findings.
        write_skill(skills / "_draft-bad-draft", "bad-draft",
                    "Another prototype procedure.")

    (skills / "REGISTRY.md").write_text(
        "# Registry\n\n" + "".join(f"- `{n}/SKILL.md`\n" for n in names),
        encoding="utf-8")

    cfg = {"tool_domains": ["grandma3", "mikrotik", "osc", "dmx", "touchdesigner"],
           # `gone-skill` is on the baseline but not on disk -> the baseline must not
           # be allowed to keep dead lines, or it stops being a ratchet.
           "legacy": ["legacy-rig-skill", "graduated-skill", "gone-skill"]}
    (root / ".claude" / "rules").mkdir(parents=True)
    (root / ".claude" / "rules" / "skill-placement.json").write_text(
        json.dumps(cfg, indent=2), encoding="utf-8")
    return linked


def run(linter: Path, root: Path) -> dict:
    env = dict(os.environ, BRAIN_DIR=str(root))
    p = subprocess.run([sys.executable, str(linter), "--json",
                        "--skills", str(root / ".claude" / "skills")],
                       capture_output=True, text=True, encoding="utf-8", env=env)
    if not p.stdout.strip():
        raise SystemExit(f"FAIL linter produced no JSON (rc={p.returncode}): {p.stderr}")
    return json.loads(p.stdout)


def skills_of(rep: dict, cat: str):
    items = rep["findings"].get(cat)
    return None if items is None else sorted(i.get("skill", "?") for i in items)


def main() -> int:
    if len(sys.argv) > 3:
        print(__doc__.strip().splitlines()[-3], file=sys.stderr)
        return 2
    new = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else HERE / "skill-lint.py"
    old = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else None
    fails = []

    def check(label: str, got, want) -> None:
        ok = got == want
        print(f"  {'PASS' if ok else 'FAIL'}  {label}")
        if not ok:
            print(f"        got  {got}\n        want {want}")
            fails.append(label)

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "brain"
        linked = build(root, with_drafts=True)
        if not linked:
            print("  SKIP  suite symlink (this OS refused to create one)")
        rep_new = run(new, root)

        print("linter under test, tree with drafts")
        check("placement fires on the new tool-domain skill, and only there",
              skills_of(rep_new, "placement"),
              ["gone-skill", "graduated-skill", "new-desk-helper"])
        # `new-desk-helper` appears here AS WELL AS under placement, and that is right:
        # it is misplaced AND unsourced, two independent defects. The first version of
        # this fixture expected only one finding for it — the fixture was wrong, not the
        # linter, which is the reason the expectation is spelled out instead of computed.
        check("provenance fires on every unsourced new skill + the bad draft (twice)",
              skills_of(rep_new, "provenance"),
              ["_draft-bad-draft", "_draft-bad-draft", "new-desk-helper",
               "new-plain-skill"])
        check("a correct draft stays out of REGISTRY.md without a registry finding",
              [i for i in rep_new["findings"]["registry"]
               if "draft" in json.dumps(i)], [])
        check("a draft directory does not trip name-vs-directory",
              [i for i in rep_new["findings"]["frontmatter"]
               if "draft" in json.dumps(i)], [])

        if old is not None:
            rep_old = run(old, root)
            print("OLD linter on the SAME tree — negative control")
            check("old linter knows neither category",
                  [rep_old["findings"].get("placement"),
                   rep_old["findings"].get("provenance")], [None, None])
            check("old linter is red for the WRONG reasons (drafts it cannot parse)",
                  len(rep_old["findings"]["frontmatter"]) >= 2
                  and len(rep_old["findings"]["registry"]) >= 2, True)

        # The registry is GENERATED, so the draft rule must hold in the generator too —
        # otherwise the next regen writes the drafts in and the linter above never sees
        # a reason to object (it only reports drafts that are missing, not present).
        regen = HERE / "regen-skill-registry.py"
        if regen.is_file():
            p = subprocess.run([sys.executable, str(regen), "--skills",
                                str(root / ".claude" / "skills")],
                               capture_output=True, text=True, encoding="utf-8")
            reg = (root / ".claude" / "skills" / "REGISTRY.md").read_text(encoding="utf-8")
            check("regen-skill-registry leaves drafts out, keeps the rest",
                  [p.returncode, "_draft-" in reg or "good-draft" in reg,
                   "new-plain-skill" in reg], [0, False, True])

        root2 = Path(tmp) / "brain2"
        build(root2, with_drafts=False)
        if old is not None:
            print("regression guard — tree without drafts, shared categories must match")
            a, b = run(old, root2), run(new, root2)
            for cat in ("frontmatter", "budget", "collisions", "dead_refs", "registry",
                        "body_size"):
                check(f"{cat} unchanged", b["findings"][cat], a["findings"][cat])

        print("opt-out — no skill-placement.json means no ratchet, drafts still checked")
        (root2 / ".claude" / "rules" / "skill-placement.json").unlink()
        c = run(new, root2)
        check("placement silent without the config", c["findings"].get("placement"), [])
        check("provenance silent for non-drafts without the config",
              c["findings"].get("provenance"), [])
        check("ratchet reported as off", c.get("placement_ratchet"), False)

    print(f"\n{'ALL passed' if not fails else str(len(fails)) + ' FAILED: ' + ', '.join(fails)}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
