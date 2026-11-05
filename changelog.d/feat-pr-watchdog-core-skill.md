- **Skill `pr-watchdog` moves into the core: the release chain after a merge** (test: T0) (level: writer; higher:
  design - a release tool that runs the chain itself (race guard, bump, tag, pin PR, pin-check) instead of a skill
  that instructs it, not built because the chain crosses two repos with their own merge rules; debt: the instance-only
  plugin that carried the skill is unwired by each brain after the pin, outside this repo). The skill lived in an
  instance-only plugin as a local deviation from the one-system rule; the operator decided on 2026-11-02 that it
  belongs in the core. Ported generic and in English: no repo names - the marketplace is the brain's first marketplace
  (the resolution of `scripts/eco_owner.py`), the plugin's source repo comes from its `marketplace.json`,
  `pin-check.sh` runs in the brain's copy of the marketplace repo. Steps instruct; the two dated incidents (release
  race, a pin left behind its tag) stand under `## Evidence`. `skills/REGISTRY.md` regenerated (28 skills);
  `skill-lint.py` 0 findings.
