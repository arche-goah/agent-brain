# Directory Structure, Progressive Disclosure, Scripts & Resources

Moved verbatim from SKILL.md (progressive disclosure, 2026-08-10).

## Directory Structure

### Minimal Skill (Required)
```
~/.claude/skills/                    # Personal skills location
└── my-skill/                        # Skill directory (MUST be at top level!)
    └── SKILL.md                     # REQUIRED: Main skill file
```

**IMPORTANT**: Skills MUST be directly under `~/.claude/skills/[skill-name]/`.
Claude Code does NOT support nested subdirectories or namespaces!

### Full-Featured Skill (Recommended)
```
~/.claude/skills/
└── my-skill/                        # Top-level skill directory
        ├── SKILL.md                 # REQUIRED: Main skill file
        ├── README.md                # Optional: Human-readable docs
        ├── scripts/                 # Optional: Executable scripts
        │   ├── setup.sh
        │   ├── validate.js
        │   └── deploy.py
        ├── resources/               # Optional: Supporting files
        │   ├── templates/
        │   │   ├── api-template.js
        │   │   └── component.tsx
        │   ├── examples/
        │   │   └── sample-output.json
        │   └── schemas/
        │       └── config-schema.json
        └── docs/                    # Optional: Additional documentation
            ├── ADVANCED.md
            ├── TROUBLESHOOTING.md
            └── API_REFERENCE.md
```

### Skills Locations

**Personal Skills** (available across all projects):
```
~/.claude/skills/
└── [your-skills]/
```
- **Path**: `~/.claude/skills/` or `$HOME/.claude/skills/`
- **Scope**: Available in all projects for this user
- **Version Control**: NOT committed to git (outside repo)
- **Use Case**: Personal productivity tools, custom workflows

**Project Skills** (team-shared, version controlled):
```
<project-root>/.claude/skills/
└── [team-skills]/
```
- **Path**: `.claude/skills/` in project root
- **Scope**: Available only in this project
- **Version Control**: SHOULD be committed to git
- **Use Case**: Team workflows, project-specific tools, shared knowledge

## Progressive Disclosure Architecture

Claude Code uses a **3-level progressive disclosure system** to scale to 100+ skills without context penalty:

### Level 1: Metadata (Name + Description)
**Loaded**: At Claude Code startup, always
**Size**: ~200 chars per skill
**Purpose**: Enable autonomous skill matching
**Context**: Loaded into system prompt for ALL skills

```yaml
---
name: "API Builder"                   # 11 chars
description: "Creates REST APIs..."   # ~50 chars
---
# Total: ~61 chars per skill
# 100 skills = ~6KB context (minimal!)
```

### Level 2: SKILL.md Body
**Loaded**: When skill is triggered/matched
**Size**: ~1-10KB typically
**Purpose**: Main instructions and procedures
**Context**: Only loaded for ACTIVE skills

```markdown
# API Builder

## What This Skill Does
[Main instructions - loaded only when skill is active]

## Quick Start
[Basic procedures]

## Step-by-Step Guide
[Detailed instructions]
```

### Level 3+: Referenced Files
**Loaded**: On-demand as Claude navigates
**Size**: Variable (KB to MB)
**Purpose**: Deep reference, examples, schemas
**Context**: Loaded only when Claude accesses specific files

```markdown
# In SKILL.md
See [Advanced Configuration](docs/ADVANCED.md) for complex scenarios.
See [API Reference](docs/API_REFERENCE.md) for complete documentation.
Use template: `resources/templates/api-template.js`

# Claude will load these files ONLY if needed
```

**Benefit**: Install 100+ skills with ~6KB context. Only active skill content (1-10KB) enters context.

## Recommended 4-Level SKILL.md Content Structure

```markdown
---
name: "Your Skill Name"
description: "What it does and when to use it"
---

# Your Skill Name

## Level 1: Overview (Always Read First)
Brief 2-3 sentence description of the skill.

## Prerequisites
- Requirement 1
- Requirement 2

## What This Skill Does
1. Primary function
2. Secondary function
3. Key benefit

---

## Level 2: Quick Start (For Fast Onboarding)

### Basic Usage
# Simplest use case
command --option value

### Common Scenarios
1. **Scenario 1**: How to...
2. **Scenario 2**: How to...

---

## Level 3: Detailed Instructions (For Deep Work)

### Step-by-Step Guide
Setup → Configuration → Execution, each with commands and expected output.

### Advanced Options
Custom configuration, integration.

---

## Level 4: Reference (Rarely Needed)

### Troubleshooting
Per issue: Symptoms / Cause / Solution with fix command.

### Complete API Reference
See [API_REFERENCE.md](docs/API_REFERENCE.md)

### Examples, Related Skills, Resources
Links only — content lives in the referenced files.
```

### Progressive Disclosure Writing

**Keep Level 1 Brief** (Overview):
```markdown
## What This Skill Does
Creates production-ready React components with TypeScript, hooks, and tests in 3 steps.
```

**Level 2 for Common Paths** (Quick Start): the 80% use case as one command.

**Level 3 for Details** (Step-by-Step): numbered steps with explanations.

**Level 4 for Edge Cases** (Reference):
```markdown
## Advanced Configuration
For complex scenarios like HOCs, render props, or custom hooks, see [ADVANCED.md](docs/ADVANCED.md).
```

## Adding Scripts and Resources

### Scripts Directory

**Purpose**: Executable scripts that Claude can run
**Location**: `scripts/` in skill directory
**Usage**: Referenced from SKILL.md

```bash
# In skill directory
scripts/
├── setup.sh          # Initialization script
├── validate.js       # Validation logic
├── generate.py       # Code generation
└── deploy.sh         # Deployment script
```

Reference from SKILL.md:
```markdown
## Setup
Run the setup script:
./scripts/setup.sh

## Validation
Validate your configuration:
node scripts/validate.js config.json
```

### Resources Directory

**Purpose**: Templates, examples, schemas, static files
**Location**: `resources/` in skill directory
**Usage**: Referenced or copied by scripts

```bash
resources/
├── templates/
│   ├── component.tsx.template
│   ├── test.spec.ts.template
│   └── story.stories.tsx.template
├── examples/
│   ├── basic-example/
│   ├── advanced-example/
│   └── integration-example/
└── schemas/
    ├── config.schema.json
    └── output.schema.json
```

Reference from SKILL.md:
```markdown
## Templates
Use the component template:
cp resources/templates/component.tsx.template src/components/MyComponent.tsx

## Examples
See working examples in `resources/examples/`:
- `basic-example/` - Simple component
- `advanced-example/` - With hooks and context
```

## File References and Navigation

Claude can navigate to referenced files automatically. Use these patterns:

### Markdown Links
```markdown
See [Advanced Configuration](docs/ADVANCED.md) for complex scenarios.
See [Troubleshooting Guide](docs/TROUBLESHOOTING.md) if you encounter errors.
```

### Relative File Paths
```markdown
Use the template located at `resources/templates/api-template.js`
See examples in `resources/examples/basic-usage/`
```

### Inline File Content
```markdown
## Example Configuration
See `resources/examples/config.json`:
{
  "option": "value"
}
```

**Best Practice**: Keep SKILL.md lean (~2-5KB). Move lengthy content to separate files and reference them. Claude will load only what's needed.
