# Onboarding — from zero to your own brain

This is the human entry point into a brain setup built on this repo. Work through it
top to bottom; every step ends with a measurement, and only a green measurement moves
you forward. A Claude Code session started in this repo (or later in your fresh brain)
can execute these steps for you — you explain where you are, it runs the commands and
re-measures. The scripts referenced here all live in this repo.

Throughout this document, `your-org` is a placeholder — replace it with the GitHub
organization that hosts your marketplace and private repos.

## 0. Prerequisites

Before anything else you need, in this order:

- **A GitHub account**, with any invitations to your org's private repos accepted.
- **Node >= 23.6** (nodejs.org) — suite MCP servers rely on native type stripping.
- **git** (git-scm.com).
- **Python 3** (stock install, stdlib only — the verify scripts need no packages).
- **`gh` CLI, logged in over SSH** (`gh auth login`, choose SSH as the protocol —
  gh generates the key and uploads it to GitHub for you).
- **Claude Code** (claude.com/claude-code).

Windows: after EVERY installation, open a new terminal. Windows does not propagate
PATH changes to already-running processes — otherwise the preflight reports tools as
missing although they are installed, and you install things twice.

**SSH is mandatory, not a recommendation.** A token-/HTTPS-only login looks
functional but breaks two things: `claude plugin install` (clones over SSH) and the
automatic marketplace updates (the background refresh cannot use HTTPS credentials).
The preflight only passes once `ssh -T git@github.com` greets you by name.

## 1. Preflight — measure, do not assume

```
bash scripts/preflight.sh
```

It checks OS, Node version, git (plus `core.longpaths` on Windows), Python, `gh`
login, proven SSH access to GitHub, and the `claude` CLI. It installs nothing. For
every red line it prints the exact fix; run it again after each fix — "I did it" is
not evidence, only the green re-check is. (On Windows, `scripts/preflight.ps1` is the
same set of checks for the PowerShell view; the Git Bash edition is authoritative.)

## 2. Marketplace registration — the default is ONLY the core

Your org publishes plugins through a marketplace repo that pins released tags of this
repo. Register it once, then install the core plugin:

```
claude plugin marketplace add your-org/claude-marketplace
claude plugin install brain-core@your-org
```

**Restart Claude Code afterwards.** Skills, hooks and the output style of a freshly
installed plugin are only read on the next start. Check with `claude plugin list`:
`brain-core` must be installed AND enabled.

Everything else in the marketplace (tool-domain suites) is opt-in — install a suite
only when you explicitly want and need it (step 4).

## 3. Your own private brain

```
bash scripts/bootstrap-brain.sh ~/Projects/<your-name>-brain
```

This creates your brain from `templates/` (CLAUDE.md skeleton, instance rules, empty
feedback file, settings with hooks) and mounts this repo as the `core/` submodule.
One hand step afterwards (the template is deliberately generic): in your new brain's
`.claude/settings.json`, replace the example marketplace `your-org` with your real
org — a Claude session in the brain does that for you if you ask.

**Your brain is yours:** a private repo under YOUR account, never shared. Creating
the remote and pushing stays with you.

Then start `claude` IN the brain directory and accept the trust dialog. Both
mistakes look identical ("style/hooks do nothing"): start in the wrong directory and
the project settings never apply; start in the right one and they stay silent until
the trust dialog is accepted. Only after trust is the brain actually on.

## 4. Optional: install a suite

Suites (one plugin per tool domain) are never part of the default scope. When you
need one:

```
claude plugin install <suite>@your-org
bash scripts/suite-install.sh <suite>
```

`suite-install.sh` puts the suite's working checkout at its released tag — it never
consumes an untagged state. Restart Claude Code after any plugin install.

## 5. Shell start: `claude` always lands in the brain

The most common stumbling block AFTER onboarding: new terminal, type `claude` — and
it starts a bare session in `$HOME`, without rules, hooks or style. Against that:

```
bash scripts/setup-shell-start.sh ~/Projects/<your-name>-brain
```

It writes a marked block (`brain shell-start`) into your shell profiles: every new
shell that starts in `$HOME` changes into the brain. Working in another repo stays
untouched — the block only fires on a start in `$HOME`. To remove it, delete the
marked blocks.

## 6. Verify + report

```
bash scripts/onboarding-verify.sh ~/Projects/<your-name>-brain
```

This checks the 11 points of `docs/onboarding-contract.md` and writes
`onboarding-report.txt` into your brain. Suite checks (6+7) read `SKIP` on a
core-only onboarding — that is correct, not red. Send the report back to whoever
invited you; it answers "does it run on your machine?" without screenshots.

## Afterwards: the maintenance rhythm

- Weekly, never on a show day: `bash core/scripts/brain-update.sh` from your brain —
  one command that follows the marketplace pin on every layer (marketplaces, plugins
  with provenance check, `core/` submodule on the pinned tag, ecosystem.json).
  NOT `git submodule update --remote core`: that tracks `main` instead of the pin.
- Own changes to a suite or to the core: branch in that repo, PR, CI green, merge,
  tag, marketplace pin. Never in the plugin cache, never as a copy in your brain.
  The working checkout belongs at `~/Projects/<repo-name>` — the repo's name, no
  abbreviation, so `ecosystem.json` entries match their repos and the next person
  finds the checkout.
- Details: `core/CONVENTIONS.md` — it sits in your brain after step 3.
