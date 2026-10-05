#!/usr/bin/env python3
"""DETERMINISTIC skill linter for .claude/skills/ — reproducible, read-only, stdlib.

WHY (review finding 2026-08-02): our audit suite is purely LLM-based and therefore
not reproducible. For skills there is a second gap on top — with 95 skills, the
dangerous defects are NOT in the individual skill, but BETWEEN them: colliding
auto-fire triggers, a silently blown listing budget, dead references.
`AgriciDaniel/skill-forge` validates exactly ONE directory at a time and knows none of
these three classes (grepped repo-wide: no hit for collision/overlap/budget).
The shape is borrowed from there, not the code — whose regex-YAML parser silently
drops the rest on multi-line descriptions and still reports score 100.

CHECKS:
  1. frontmatter   name + description present; name == folder name; kebab-case;
                   reserved word 'claude'; length limits
  2. budget        sum of name+description against skillListingBudgetFraction —
                   over the limit the listing gets cut off SILENTLY
  3. collisions    pairwise trigger similarity of the descriptions (jaccard over
                   meaningful tokens) — two skills that fire on the same thing
  4. dead_refs     references/*, scripts/* referenced in the SKILL.md exist
  5. registry      REGISTRY.md <-> directories (both directions)
  6. placement     a tool-domain skill that lives in the private brain instead of the
                   domain's suite (CONVENTIONS §11) — plus the ratchet direction:
                   a baseline entry that is no longer needed has to LEAVE the baseline
  7. provenance    a skill whose frontmatter carries no `provenance:` — a procedure
                   whose steps name no source is a draft, not a verified skill

WHY 6+7 (measured 2026-08-19/20, incident `macro5001`): an instance wrote four skills
out of its own live-session memory, straight into its private brain. One of them was
written a DAY AFTER the decision it silently contradicts, and the instance then followed
its own skill instead of re-reading the primary source. Two rules already said this was
wrong — CONVENTIONS §11 ("a new capability never starts life inside a private brain")
and the skill-first order — and neither had a carrier: this linter checked STRUCTURE
only, never placement and never where a step's content came from. Prose lost against a
file on disk, which is the whole class.

Both checks are a RATCHET, not a verdict on the existing set (same shape as
english-legacy.txt): `.claude/rules/skill-placement.json` freezes the skills that
predate the rule. Without that file the placement check has no domain vocabulary and
the provenance check applies to DRAFTS only — a brain that has not opted in stays
green instead of going permanently red, which is what gets a linter ignored.

Draft convention (the reason a draft may exist at all): directory `_draft-<name>` with
`status: draft` + `provenance:` in the frontmatter. A draft may be used, but it never
wins against a primary source, a ledger or a live measurement.

Usage: skill-lint.py [--skills DIR] [--json] [--collision-threshold 0.35] [--ctx 200000]
Exit 0 = clean, 1 = findings, 2 = unreadable.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from itertools import combinations
from pathlib import Path

# Lints the INSTANCE repo (its .claude/skills + settings). Run from the instance root,
# or set BRAIN_DIR. The core checkout only carries the tool.
import os
ROOT = Path(os.environ.get("BRAIN_DIR", Path.cwd())).resolve()
NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
# (?<![\w/.-]) = word boundary before it. Without it, the first run 2026-08-02 caught
# two false positives: "subscripts/superscripts." from prose, and the path SUFFIX of
# paths pointing at OTHER skills (.claude/skills/whisper-cut-ffmpeg/scripts/transcribe.sh).
REF_RE = re.compile(r"(?<![\w/.-])(?:references|scripts|assets)/[A-Za-z0-9._/-]*[A-Za-z0-9_-]")
REG_LINK = re.compile(r"`?([a-z0-9][a-z0-9-]*)/SKILL\.md`?|\|\s*`?([a-z0-9][a-z0-9-]*)`?\s*\|")
MAX_NAME, MAX_DESC, MAX_BODY_LINES = 64, 1024, 500
DRAFT_PREFIX = "_draft-"
# Instance data, not core knowledge: WHICH tool domains this brain has suites for, and
# WHICH pre-existing skills the ratchet exempts. Same split as premise-patterns.json /
# time-patterns.json — vocabulary is instance-owned, the mechanism is not.
PLACEMENT_CFG = ROOT / ".claude/rules/skill-placement.json"

# tokens that say nothing about trigger similarity
STOP = set("""use when the a an and or for of to in on with without this that these those
it its as by from at into via per if then than not no nor but so such is are be been being
user users claude skill skills auto fires fire trigger triggers usage used using only also
nicht oder und der die das den dem des ein eine einer eines fuer bei mit ohne auf aus vor
nach ueber unter zum zur wenn dann als wie was wer wo ist sind war waren wird werden kann
koennen soll sollen muss muessen darf duerfen nur auch noch schon bereits sowie beim""".split())


def frontmatter(text: str) -> dict:
    """Frontmatter reader that does not swallow MULTI-LINE values.
    The exact defect where skill-forge's parser silently checks the wrong thing:
    plain-continuation and block scalars (>, |) must be read along with it."""
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end == -1:
        return {}
    out, key, buf = {}, None, []
    for raw in text[3:end].splitlines():
        if not raw.strip():
            continue
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", raw)
        if m and not raw[:1].isspace():
            if key:
                out[key] = " ".join(buf).strip()
            key, first = m.group(1), m.group(2).strip()
            buf = [] if first in (">", "|", ">-", "|-", "") else [first]
        elif key:
            buf.append(raw.strip())
    if key:
        out[key] = " ".join(buf).strip()
    return {k: v.strip("\"'") for k, v in out.items()}


def tokens(s: str) -> set[str]:
    return {w for w in re.findall(r"[a-zA-Zaeoeuess]{4,}", s.lower()) if w not in STOP}


def placement_cfg(path: Path) -> tuple[list[str], set[str], bool]:
    """(tool_domains, legacy_baseline, opted_in). Absent/broken file = not opted in."""
    try:
        cfg = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return [], set(), False
    return ([str(t).lower() for t in cfg.get("tool_domains", [])],
            {str(s) for s in cfg.get("legacy", [])}, True)


def domain_hits(haystack: str, domains: list[str]) -> list[str]:
    """Whole-token match only. Substring matching turns 'osc' into a hit inside
    'kiosk' and 'dmx' into one inside any hex blob; the false positives are what
    stops people running a linter."""
    low = haystack.lower()
    return sorted({d for d in domains
                   if re.search(rf"(?<![a-z0-9]){re.escape(d)}(?![a-z0-9])", low)})


def lint(skills: Path, thresh: float, ctx: int) -> dict:
    # `body_size` is INFO, not a defect — deliberately does NOT feed into the exit code.
    # A linter that stays permanently red over non-defects gets ignored.
    f: dict[str, list] = {k: [] for k in
                          ("frontmatter", "budget", "collisions", "dead_refs", "registry",
                           "placement", "provenance", "body_size")}
    meta: dict[str, dict] = {}
    domains, legacy, opted_in = placement_cfg(PLACEMENT_CFG)

    # Skills that live in a suite repo are mounted here as symlinks. On a CI runner the
    # sibling repo is not checked out, so the link dangles. That is not a defect of THIS
    # repo — the suite's own CI lints it — but before 2026-08-03 it made this linter red
    # for 17 skills and stayed red through several pushes, unnoticed. A checker that
    # cannot tell "missing" from "lives elsewhere" gets ignored, which is worse.
    elsewhere = sorted(p.name for p in skills.iterdir()
                       if p.is_symlink() and not p.exists())

    for d in sorted(p for p in skills.iterdir() if p.is_dir()):
        sk = d / "SKILL.md"
        if not sk.is_file():
            f["registry"].append({"issue": "directory without SKILL.md", "dir": d.name})
            continue
        text = sk.read_text(encoding="utf-8", errors="replace")
        fm = frontmatter(text)
        name, desc = fm.get("name", ""), fm.get("description", "")
        # A draft directory carries the prefix; its `name:` is the skill it will become,
        # so the identity checks below compare against the STRIPPED name.
        is_draft = d.name.startswith(DRAFT_PREFIX)
        base = d.name[len(DRAFT_PREFIX):] if is_draft else d.name

        if not name:
            f["frontmatter"].append({"skill": d.name, "issue": "name missing"})
        else:
            if name != base:
                f["frontmatter"].append({"skill": d.name, "issue": "name != directory",
                                         "name": name})
            if not NAME_RE.match(name):
                f["frontmatter"].append({"skill": d.name, "issue": "not kebab-case",
                                         "name": name})
            if "claude" in name.lower():
                f["frontmatter"].append({"skill": d.name,
                                         "issue": "reserved word 'claude' in the name"})
            if len(name) > MAX_NAME:
                f["frontmatter"].append({"skill": d.name, "issue": "name too long",
                                         "len": len(name), "max": MAX_NAME})
        if not desc:
            f["frontmatter"].append({"skill": d.name, "issue": "description missing"})
        elif len(desc) > MAX_DESC:
            f["frontmatter"].append({"skill": d.name, "issue": "description too long",
                                     "len": len(desc), "max": MAX_DESC})

        body = text[text.find("\n---", 3) + 4:] if text.startswith("---") else text
        n_lines = len(body.splitlines())
        if n_lines > MAX_BODY_LINES:
            f["body_size"].append({"skill": d.name, "issue": "SKILL.md body very long "
                                   "(check progressive disclosure)",
                                   "lines": n_lines, "max": MAX_BODY_LINES})

        # NOTE: check ONLY skills that have their own resource folder. The first run
        # 2026-08-02 reported 31 "dead" refs that were mostly PROSE about foreign paths
        # (e.g. `scripts/eng.sh` of the MA3 suite, which really lives under
        # src/grandma3-mcp/scripts/ in the other repo). If a skill does not even have
        # the folder, any mention of it is obviously not a reference to its own resource.
        own = {sub for sub in ("references", "scripts", "assets") if (d / sub).is_dir()}
        for ref in sorted(set(REF_RE.findall(body))):
            if ref.split("/", 1)[0] not in own:
                continue
            if not (d / ref).exists():
                f["dead_refs"].append({"skill": d.name, "ref": ref})

        meta[d.name] = {"name": name, "desc": desc, "cost": len(name) + len(desc),
                        "tok": tokens(desc),
                        # A skill mounted from a suite is a SYMLINK here; a skill born in
                        # this brain is a real directory. That is the whole placement
                        # discriminator, and it is a fact on disk rather than a judgement.
                        "local": not d.is_symlink(), "draft": is_draft,
                        "status": fm.get("status", ""),
                        "prov": bool(fm.get("provenance", "").strip()),
                        "domains": domain_hits(f"{name} {desc}", domains)}

    # 2. listing budget
    total = sum(m["cost"] for m in meta.values())
    approx_tok = total // 4
    try:
        cfg = json.loads((ROOT / ".claude/settings.json").read_text(encoding="utf-8"))
        frac = float(cfg.get("skillListingBudgetFraction", 0.04))
    except Exception:
        frac = 0.04
    budget_tok = int(ctx * frac)
    pct = 100.0 * approx_tok / budget_tok if budget_tok else 0
    # NOTE: the budget hangs off the CONTEXT WINDOW of the running model, not the skill
    # count. 2026-08-02 first computed against 200k and reported "91% — critical"; the
    # real run here is on opus[1m], so ~18%. The real risk case is therefore a MODEL
    # SWITCH: with a 200k model the same set tips over immediately, and the overflow is
    # silent.
    pct_small = 100.0 * approx_tok / int(200_000 * frac)
    top = sorted(meta.items(), key=lambda kv: -kv[1]["cost"])[:5]
    if pct >= 85 or pct_small >= 85:
        f["budget"].append({
            "issue": ("listing budget nearly/fully exhausted — overflow gets cut SILENTLY"
                      if pct >= 85 else
                      "ok for this context window, but a 200k model would overflow"),
            "characters": total, "approx_tokens": approx_tok,
            "budget_tokens": budget_tok, "usage_pct": round(pct),
            "at_200k_model_pct": round(pct_small),
            "largest": [{"skill": k, "characters": v["cost"]} for k, v in top]})

    # 3. trigger collisions
    for (a, ma), (b, mb) in combinations(sorted(meta.items()), 2):
        if not ma["tok"] or not mb["tok"]:
            continue
        inter = ma["tok"] & mb["tok"]
        union = ma["tok"] | mb["tok"]
        j = len(inter) / len(union)
        if j >= thresh:
            f["collisions"].append({"a": a, "b": b, "jaccard": round(j, 2),
                                    "shared": sorted(inter)[:12]})
    f["collisions"].sort(key=lambda x: -x["jaccard"])

    # 6./7. placement + provenance (see module docstring for the incident)
    for skill, m in sorted(meta.items()):
        if m["draft"]:
            # A draft is by definition new, so the baseline never covers it. Both
            # halves matter: `status: draft` is what stops it outranking a primary
            # source, `provenance` is what makes its steps checkable at all.
            if m["status"] != "draft":
                f["provenance"].append({"skill": skill, "issue":
                                        f"{DRAFT_PREFIX} directory without 'status: draft'"})
            if not m["prov"]:
                f["provenance"].append({"skill": skill, "issue":
                                        "draft without 'provenance:' — a step without a "
                                        "source is not a procedure"})
            continue
        if not m["local"] or skill in legacy:
            continue  # lives in a suite (linted there), or predates the rule
        if m["domains"]:
            f["placement"].append({"skill": skill, "issue":
                                   "tool-domain skill born in the private brain — "
                                   "CONVENTIONS §11 puts it in that domain's suite",
                                   "domains": m["domains"]})
        if opted_in and not m["prov"]:
            f["provenance"].append({"skill": skill, "issue":
                                    "new local skill without 'provenance:' — name a "
                                    "source per procedure step (measured/derived/assumed)"})

    # The ratchet only counts if the baseline can SHRINK. Without these two, a frozen
    # list quietly becomes a permanent exemption — the failure mode english-legacy.txt
    # was built to avoid.
    for stale in sorted(legacy - set(meta)):
        f["placement"].append({"skill": stale, "issue":
                               "baseline names a skill that no longer exists — "
                               "remove the line, the baseline only shrinks"})
    for skill in sorted(legacy & set(meta)):
        m = meta[skill]
        if not m["local"] or (m["prov"] and not m["domains"]):
            f["placement"].append({"skill": skill, "issue":
                                   "baseline entry is no longer needed (moved to a suite "
                                   "or carries provenance) — remove the line"})

    # 5. registry <-> directories
    reg = skills / "REGISTRY.md"
    if not reg.is_file():
        f["registry"].append({"issue": "REGISTRY.md missing"})
    else:
        rt = reg.read_text(encoding="utf-8", errors="replace")
        listed = {m for pair in REG_LINK.findall(rt) for m in pair if m}
        # Drafts stay OUT of the registry on purpose: the registry is the list of
        # verified skills, and a draft that appears there has already won the rank it
        # is not supposed to have.
        for miss in sorted(s for s in set(meta) - listed if not meta[s]["draft"]):
            f["registry"].append({"issue": "skill not in REGISTRY.md", "skill": miss})
        for extra in sorted(listed - set(meta)):
            if extra in {"skills", "claude"} or extra in elsewhere:
                continue  # see `elsewhere` above: mounted from a suite, linted there
            f["registry"].append({"issue": "REGISTRY.md names a missing skill",
                                  "skill": extra})

    return {"findings": f, "counts": {k: len(v) for k, v in f.items()},
            "scanned": len(meta), "elsewhere": elsewhere,
            "placement_ratchet": opted_in,
            "budget_pct": round(pct)}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--skills", type=Path, default=ROOT / ".claude/skills")
    ap.add_argument("--collision-threshold", type=float, default=0.35)
    ap.add_argument("--ctx", type=int, default=200_000)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    if not a.skills.is_dir():
        print(f"ERROR: skills directory not found: {a.skills}", file=sys.stderr)
        return 2

    rep = lint(a.skills, a.collision_threshold, a.ctx)
    if a.json:
        print(json.dumps(rep, indent=2, ensure_ascii=False))
    else:
        hard = sum(v for k, v in rep["counts"].items() if k != "body_size")
        total = sum(rep["counts"].values())
        print(f"skill-lint: {rep['scanned']} skills checked, {hard} finding(s) "
              f"({rep['counts']['body_size']} info) "
              f"(listing budget ~{rep['budget_pct']}%)")
        if rep["elsewhere"]:
            print(f"   {len(rep['elsewhere'])} mounted from a suite, not resolvable "
                  f"here (linted there): {', '.join(rep['elsewhere'])}")
        for cat, items in rep["findings"].items():
            if not items:
                continue
            print(f"\n!! {cat} ({len(items)}):")
            for it in items[:15]:
                print("   " + json.dumps(it, ensure_ascii=False))
            if len(items) > 15:
                print(f"   ... and {len(items) - 15} more")
        if not rep["placement_ratchet"]:
            print(f"   placement/provenance ratchet not enabled "
                  f"({PLACEMENT_CFG} absent) — drafts are still checked")
        if hard == 0:
            print("no defects (frontmatter, budget, collisions, refs, registry, "
                  "placement, provenance).")
    hard = sum(v for k, v in rep["counts"].items() if k != "body_size")
    return 1 if hard else 0


if __name__ == "__main__":
    sys.exit(main())
