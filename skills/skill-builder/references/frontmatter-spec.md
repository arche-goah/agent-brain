# YAML Frontmatter — Full Specification

Moved verbatim from SKILL.md (progressive disclosure, 2026-08-10). The load-bearing
essentials (required fields, kebab-case rule) stay in SKILL.md; this file carries the
long form.

## Field Requirements

**`name`** (REQUIRED):
- **Type**: String
- **Max Length**: 64 characters
- **Format**: **kebab-case** (lowercase, digits, hyphens) — **MUST exactly match the
  directory name** (`.claude/skills/<name>/SKILL.md`)
- **Reserved**: the word `claude` does not belong in the name
- **Examples**:
  - ✅ `api-documentation-generator`
  - ✅ `session-close`, `multi-device-messung` (these are the names of our real skills)
  - ❌ `"API Documentation Generator"` (Title Case — does not match the directory)
  - ❌ `skill-1` (not descriptive)

**`description`** (REQUIRED):
- **Type**: String
- **Max Length**: 1024 characters
- **Format**: Plain text or minimal markdown
- **Content**: MUST include:
  1. **What** the skill does (functionality)
  2. **When** Claude should invoke it (trigger conditions)
- **Usage**: Loaded into Claude's system prompt for autonomous matching
- **Best Practice**: Front-load key trigger words, be specific about use cases
- **Examples**:
  - ✅ "Generate OpenAPI 3.0 documentation from Express.js routes. Use when creating API docs, documenting endpoints, or building API specifications."
  - ✅ "Create React functional components with TypeScript, hooks, and tests. Use when scaffolding new components or converting class components."
  - ❌ "A comprehensive guide to API documentation" (no "when" clause)
  - ❌ "Documentation tool" (too vague)

## YAML Formatting Rules

```yaml
---
# ✅ CORRECT: Simple string
name: "API Builder"
description: "Creates REST APIs with Express and TypeScript."

# ✅ CORRECT: Multi-line description
name: "Full-Stack Generator"
description: "Generates full-stack applications with React frontend and Node.js backend. Use when starting new projects or scaffolding applications."

# ✅ CORRECT: Special characters quoted
name: "JSON:API Builder"
description: "Creates JSON:API compliant endpoints: pagination, filtering, relationships."

# ❌ WRONG: Missing quotes with special chars
name: API:Builder  # YAML parse error!

# ❌ WRONG: Extra fields (ignored but discouraged)
name: "My Skill"
description: "My description"
version: "1.0.0"       # NOT part of spec
author: "Me"           # NOT part of spec
tags: ["dev", "api"]   # NOT part of spec
---
```

**Critical**: Only `name` and `description` are used by Claude. Additional fields are ignored.

## Writing Effective Descriptions

**Front-Load Keywords**:
```yaml
# ✅ GOOD: Keywords first
description: "Generate TypeScript interfaces from JSON schema. Use when converting schemas, creating types, or building API clients."

# ❌ BAD: Keywords buried
description: "This skill helps developers who need to work with JSON schemas by providing a way to generate TypeScript interfaces."
```

**Include Trigger Conditions**:
```yaml
# ✅ GOOD: Clear "when" clause
description: "Debug React performance issues using Chrome DevTools. Use when components re-render unnecessarily, investigating slow updates, or optimizing bundle size."

# ❌ BAD: No trigger conditions
description: "Helps with React performance debugging."
```

**Be Specific**:
```yaml
# ✅ GOOD: Specific technologies
description: "Create Express.js REST endpoints with Joi validation, Swagger docs, and Jest tests. Use when building new APIs or adding endpoints."

# ❌ BAD: Too generic
description: "Build API endpoints with proper validation and testing."
```
