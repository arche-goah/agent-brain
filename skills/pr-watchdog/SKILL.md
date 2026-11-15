---
name: pr-watchdog
description: Maintainer release chain AFTER a merge in the core or in a suite the brain maintains - version bump, CHANGELOG, tag, marketplace pin, pin check, race guard against a second instance. Use when a merged state is to be shipped ("cut a release", "tag it", "move the pin", German "release schneiden", "taggen", "pin nachziehen") AND the instance's release rules allow it. NOT for watching or handling incoming PRs - that is collab-watch; NOT for re-measuring a collaborator's hardware claims - that is pr-live-verify.
---

# Release chain after a merge (maintainer part)

`collab-watch` discovers PRs, reviews and merges them by the repo's ownership rules.
This skill starts where that ends: a merged state that is to reach the brains. A release
is the race-prone step — every brain watching the repo sees the same merges — and it is
finished only when the marketplace pin names the new tag, not when the tag is pushed.

## When

A merged state is to be shipped AND the instance's release rules allow this release:
- a stable core release or a stable pin is the operator's word (the instance's
  operator-only list, `.claude/rules/operator-only.json`);
- a beta tag and a suite release follow the rules the instance states for them
  (who may cut, when a strand is ripe, which checks per OS).

Without that release: prepare everything below up to the tag, present it, and stop.

## Where the repos come from

No repo name is written into this skill. The marketplace is the brain's FIRST marketplace
(`extraKnownMarketplaces` in `.claude/settings.json`, then the user settings — the same
resolution as `scripts/eco_owner.py`); the plugin and its source repo come from that
marketplace's `marketplace.json`; the brain's working copy of the marketplace repo is
where its `scripts/pin-check.sh` runs. If the brain names no marketplace, the chain ends
at the tag and says so.

## Release chain

0. **Scope first, the moment release prep is ordered** (why: Evidence, 2026-11-06).
   `python3 core/scripts/release-scope.py open X.Y.Z` in the brain, then `add` every PR,
   branch and ledger id this release carries and `exclude <item> "<reason>"` what it
   deliberately leaves out — what stays out is the operator's call: ask with the list, then
   `RELEASE_SCOPE_EXCLUDE_OK='"<their words>" <YYYY-MM-DD>'` (the tool refuses without it). While the scope is open, `helpers/release-freeze-gate.cjs`
   holds new core branches outside it. Run `release-scope.py check --core-clone <clone>
   --version X.Y.Z` BEFORE the OS hand-check request goes out and again before the tag
   (release preflight check 11 runs it with `RELEASE_SCOPE_BRAIN=<brain root>`); exit 1
   names each open item of this instance that is neither in nor out. `close` after the
   pin (step 3) ends the freeze.
1. **Race guard before the cut** (why: Evidence, 2026-08-10). `git fetch --tags` and
   `git tag -l vX.Y.Z` in the plugin repo — when the tag exists, the release happened.
   When a release PR (`chore: release` / a `release/*` branch) is already open, comment
   THERE instead of opening a second one. The loser of a race closes its duplicate with
   a comment naming the tag, the pin and the time — never with a force push.
2. **Version bump, CHANGELOG header, release commit** on a branch with a PR (a protected
   main refuses direct edits); `scripts/release-preflight.sh vX.Y.Z` green; then the tag.
3. **Marketplace pin — part of the release, never an optional follow-up** (why:
   Evidence, 2026-08-14): a PR in the marketplace repo that moves the plugin's `ref` to
   the new tag, by that repo's own merge rules.
4. **Mechanical proof, not a word:** run `scripts/pin-check.sh` of the marketplace repo
   AFTER every tag; it reports per plugin whether the pin equals the newest tag. The
   release is done when the check is green for the plugin, not when the tag is pushed.
5. **Bring the instance along:** `core/scripts/brain-update.sh` (submodule and plugin
   update) and measure its effect check green.

## Evidence

- 2026-08-10: two brains saw the same merges and each opened a release PR for the same
  version (#44 vs #45 of the core's earlier history); the race guard in step 1 exists
  since.
- 2026-08-14: a suite was tagged v1.1.9 while its marketplace pin stayed at v1.1.7; a
  parallel Windows session pulled the old state live. Since then the pin is step 3 and
  `pin-check.sh` its proof.
- 2026-11-06: for beta 2.1.4 sixteen PRs each got their own lint and CI, the train was
  rebuilt three times, and it was closed (Windows hand check requested) while the same
  instance still had two own branches in work and two operator-released items unbuilt;
  the operator found them afterwards. Since then step 0 writes the scope down first.
- 2026-11-02: this skill lived in an instance-only plugin (as a local deviation from the
  one-system rule); the operator moved it into the core ("these should be core skills").
