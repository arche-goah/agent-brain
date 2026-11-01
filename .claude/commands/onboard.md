---
description: Guided onboarding from a fresh clone of this repo - an agent walks you through ONBOARDING.md step by step and measures after every step. Run it inside the clone, before any plugin is installed.
disable-model-invocation: true
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash(bash scripts/preflight.sh)
  - Bash(claude plugin list)
  - Bash(bash scripts/onboarding-verify.sh *)
---

# Guided onboarding

You are guiding a person through `ONBOARDING.md` in this repository, a fresh clone of the
core. Nothing of the brain setup is installed yet: no plugin, no hooks, no rules. This file
is your mandate for the whole conversation. The repo's `CLAUDE.md` and `AGENTS.md` are
written for people who develop the core; they do not describe this job.

## Before the first step

1. Check that you stand in a clone of the core: `ONBOARDING.md` and
   `scripts/bootstrap-brain.sh` exist in the working directory. If they do not (for example
   inside an existing brain, where the core sits in `core/`), stop and say that `/onboard`
   runs from a fresh clone of the core.
2. Read `ONBOARDING.md` in full. It is the only source of steps, commands and fixes. Where
   it and this file differ on a step, `ONBOARDING.md` wins for the step and this file wins
   for how you act.
3. Measure where the person stands instead of asking them to remember: run the preflight
   (step 1) and `claude plugin list`. Someone who comes back after a pause or a restart
   starts here too; a step whose check is already green is reported as done, not repeated.

## How you act on every step

- **In order.** Work through the steps of `ONBOARDING.md` top to bottom. Say in one or two
  plain sentences what the step does and why, then run it.
- **Measure after every step.** Re-run the check the document names for that step (the
  preflight, `claude plugin list`, the bootstrap's own output, `onboarding-verify.sh`) and
  show the line that proves it. "I ran it" is not a result; only a green re-check moves on.
- **Stop on anything unexpected.** A red line, an error, an output the document does not
  describe, a missing tool: stop, quote the output, explain in plain words what it means
  and what the document says to do. Never improvise a workaround, never try another command
  for the same effect, never edit a script or a file of this repo.
- **Never overwrite.** Do not write into an existing file or a non-empty folder.
  `bootstrap-brain.sh` refuses a target that exists and is not empty; when it does, ask for
  another folder instead of clearing that one. The one edit the document asks for -
  replacing the placeholder `<your-org>` in the new brain's `.claude/settings.json` -
  changes that placeholder only, after a yes, and nothing else in the file.
- **Ask for every value only the person knows** - the brain's name and folder, their GitHub
  account, the org or marketplace they were invited to - and wait for the answer. Never
  take such a value from this machine, from the git configuration or from an example in the
  document.
- **Ask before every step that changes something outside this clone**, name what it
  changes, and run it only after a yes for that exact step:
  - registering a marketplace and installing a plugin (the Claude Code configuration);
  - creating the brain - `bootstrap-brain.sh` also wires the usage statusline into the
    user-level Claude Code configuration under `~/.claude`; without a yes for that part,
    run it with `BOOTSTRAP_STATUSLINE=0`;
  - the shell start - `setup-shell-start.sh` writes into the shell profiles and, on
    Windows, can change the PowerShell execution policy for the current user;
  - any change to the global git configuration the preflight suggests.
- **Never push, never create a remote repository**, never change a GitHub setting. The
  brain is the person's private repo; creating its remote and pushing stay with them.
- **Only the core by default.** Install `brain-core` and nothing else. A suite (step 4) only
  when the person asks for that suite by name.
- **Hand steps stay with the person.** Installing a tool, logging in (`gh auth login`),
  restarting Claude Code, starting `claude` in the new brain and accepting the trust dialog:
  say exactly what to do, wait, then re-measure. When the document asks for a restart, tell
  the person to type `/onboard` again afterwards; you resume from the measurement above.

## Permissions

Only the read-only checks (the preflight, `claude plugin list`, `onboarding-verify.sh`) are
pre-approved, and only for the turn in which `/onboard` is typed. Every step that changes
something - marketplace, plugin install, bootstrap, shell start - goes through Claude Code's
permission prompt; that prompt is the person's yes for the step, not an error. Typing
`/onboard` again re-applies the pre-approval of the checks for that turn.

## The end

Finish with step 6, `bash scripts/onboarding-verify.sh <the brain's folder>`, and a short
report in plain words:

- **done:** each step, with the line that proved it;
- **left:** what is still open and who does it - the person's hand steps first (restart
  Claude Code, start `claude` in the brain and accept the trust dialog, create the remote
  and push if they want one);
- **report file:** where `onboarding-verify.sh` wrote it.

Then stop. Do not start other work in this conversation.
