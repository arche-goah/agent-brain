---
name: skill-builder
description: "Create new Claude Code Skills with proper YAML frontmatter, progressive disclosure structure, and complete directory organization. Use when you need to build custom skills for specific workflows, generate skill templates, or understand the Claude Skills specification."
---

# Skill Builder

## What This Skill Does

Creates production-ready Claude Code Skills with proper YAML frontmatter, progressive
disclosure architecture, and complete file/folder structure. This skill guides you
through building skills that Claude can autonomously discover and use across all
surfaces (Claude.ai, Claude Code, SDK, API).

This SKILL.md carries the essentials; the long-form spec lives in `references/`
(restructured 2026-08-10 per its own progressive-disclosure teaching — the file was
912 lines against the 500-line guideline):

- `references/frontmatter-spec.md` — full field spec, YAML formatting rules, description best practices
- `references/structure-and-disclosure.md` — directory layout, skill locations, the 3-level disclosure system, scripts/resources, file navigation
- `references/templates-and-examples.md` — three ready templates, real-world examples, external links

## Prerequisites

- Claude Code 2.0+ or Claude.ai with Skills support
- Basic understanding of Markdown and YAML
- Text editor or IDE

## Quick Start

```bash
# 1. Create skill directory (MUST be at top level, NOT in subdirectories!)
mkdir -p ~/.claude/skills/my-first-skill

# 2. Create SKILL.md with proper format
cat > ~/.claude/skills/my-first-skill/SKILL.md << 'EOF'
---
name: "My First Skill"
description: "Brief description of what this skill does and when Claude should use it. Maximum 1024 characters."
---

# My First Skill

## What This Skill Does
[Your instructions here]

## Quick Start
[Basic usage]
EOF

# 3. Verify skill is detected
# Restart Claude Code or refresh Claude.ai
```

## The Essentials (everything a valid skill needs)

**Frontmatter** — exactly two fields are used by Claude; extras are ignored:

```yaml
---
name: "skill-name"                    # REQUIRED: max 64 chars, kebab-case
description: "What this skill does    # REQUIRED: max 1024 chars
and when Claude should use it."       # include BOTH what & when
---
```

**`name` is kebab-case and MUST exactly match the directory name**
(`.claude/skills/<name>/SKILL.md`). The word `claude` is reserved.

> ⚠ **CORRECTED 2026-08-02.** This previously said "Human-friendly display name … Use Title
> Case" with examples like `"API Documentation Generator"`. That was **wrong** and
> contradicted our own practice: **all 95 skills in the repo use kebab-case**, because the
> name must match the directory. Found during the review of `AgriciDaniel/skill-forge`,
> whose `frontmatter-spec.md` describes it correctly. Lesson: **check teaching material
> against your own practice** — 95 counterexamples sat in the same repo.

**`description` must contain what AND when** — it is the only thing the model sees
before loading the skill. Front-load trigger words. Full guidance with good/bad
examples: `references/frontmatter-spec.md`.

**Structure**: skills live DIRECTLY under `~/.claude/skills/<name>/` (personal) or
`<project>/.claude/skills/<name>/` (project, committed) — no nesting, no namespaces.
Optional subdirs: `scripts/`, `resources/`, `docs/` or `references/`. Details:
`references/structure-and-disclosure.md`.

**Progressive disclosure, the one design rule**: keep SKILL.md lean (~2-5KB core
instructions); move lengthy content to referenced files — level 1 (name+description,
always loaded) → level 2 (SKILL.md body, loaded on trigger) → level 3 (referenced
files, loaded on demand). Full system description: `references/structure-and-disclosure.md`.

**Starting from a template**: three ready-to-copy templates (basic / with scripts /
full-featured) plus real-world examples: `references/templates-and-examples.md`.

## Validation Checklist

Before publishing a skill, verify:

**YAML Frontmatter**:
- [ ] Starts with `---`, ends with `---`, no YAML syntax errors
- [ ] `name` field (max 64 chars, kebab-case, == directory name)
- [ ] `description` field (max 1024 chars) includes "what" and "when"

**File Structure**:
- [ ] SKILL.md exists in skill directory
- [ ] Directory is DIRECTLY in `~/.claude/skills/[skill-name]/` or `.claude/skills/[skill-name]/`
- [ ] Clear, descriptive directory name; **NO nested subdirectories**

**Content Quality**:
- [ ] Overview is brief and clear; Quick Start shows the common use case
- [ ] Detailed steps are actionable; advanced content linked, not inlined
- [ ] Examples are concrete and runnable; troubleshooting covers common issues

**Progressive Disclosure**:
- [ ] Core instructions in SKILL.md (~2-5KB)
- [ ] Advanced content in separate referenced files
- [ ] Clear navigation between levels

**Testing**:
- [ ] Skill appears in Claude's skill list
- [ ] Description triggers on relevant queries
- [ ] Scripts execute successfully (if included); examples work as documented

In this repo additionally: `python3 scripts/skill-lint.py` must pass (frontmatter,
name==dir, no dead `references/` links, no trigger collision, listing budget).
