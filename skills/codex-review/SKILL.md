---
name: codex-review
description: Codex adversarial review for Claude Code via openai/codex-plugin-cc. Second pair of eyes on code, cheaper than Opus, checks 7 weak spots.
triggers:
  - codex review
  - adversarial review
  - code review
  - second opinion
  - pre-deploy check
  - bot security
  - prod readiness
  - codex
---

# Codex Adversarial Review

OpenAI Codex via plugin in Claude Code. Inspiration: "chase-h-ai-codex-adversarial-review" (Instagram, 2026-04-11 — import report not in repo).

## When to use
- **Pre-deploy** to Vercel (portfolio site)
- **Pre PM2 restart** of the Discord bot
- **Before `git push`** with critical code
- **Before grant submissions** — code reviews
- **Cost saving:** Codex is much cheaper than Opus → can run more often

## Status
- **Plugin local:** `tools/codex-plugin-cc/`
- **Repo:** https://github.com/openai/codex-plugin-cc
- **Requires:** ChatGPT subscription OR OpenAI API key + Node.js 18.18+
- **TODO:** add the OpenAI API key to `.env`

## Setup
```bash
cd tools/codex-plugin-cc
npm install
# Install the plugin in Claude Code
# (see README.md for the claude-code plugin install)

# In .env:
OPENAI_API_KEY=sk-...
```

## Commands (from codex-plugin-cc)
- `/codex:adversarial-review` — active questioning, decision challenge, risk flagging
- `/codex:rescue` — task delegation to the codex:codex-rescue subagent
- `/codex:status`, `/codex:result`, `/codex:cancel` — background job management

## Adversarial Review Pipeline (8 steps)
1. Parse arguments / flags
2. Estimate review size
3. Resolve target (which code area)
4. Collect context from the codebase
5. **Build adversarial prompt** — looks for 7 weak spots
6. Send to Codex
7. Claude Code as harness
8. Output: summary, findings, severity, recommendations, next steps

## The 7 weak spots Codex looks for
1. **Authentication** — auth bypass, token leaks
2. **Data Loss** — race conditions that lose data
3. **Rollbacks** — migration reversibility
4. **Race Conditions** — concurrent modification
5. **Degraded Dependencies** — outdated libs, security CVEs
6. **Version Skew** — client/server mismatch
7. **Observability Gap** — missing logs/metrics

## Use cases for the operator

### Portfolio site pre-deploy
```
/codex:adversarial-review --target=website/src/app
```

### Client project before a Vercel push
```
/codex:adversarial-review --target=client-project/src --severity=high
```

### Discord bot before a PM2 restart
```
cd discord-bot
/codex:adversarial-review --target=src/ --focus=security
```

## Pairs with
- `verification-before-completion` — pre-claim-check pattern
- `playwright-skill` — browser test after the adversarial review
- `feedback_pm2_bot` memory — the bot is never started directly, always via pm2

## TODO
- [ ] Get an OpenAI API key / check whether the ChatGPT subscription suffices
- [ ] Install the plugin in Claude Code
- [ ] First test on the portfolio-site code
- [ ] Document the cost comparison Codex vs Opus
