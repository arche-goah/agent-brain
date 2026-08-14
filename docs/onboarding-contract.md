# Onboarding contract — what must be TRUE after onboarding

> Target state as a file + a check against it (order fidelity #6: a gate that only
> checks its own change cannot see that the whole is broken).
> `scripts/onboarding-verify.sh` checks every line and writes `onboarding-report.txt`
> into the verified brain.
>
> **The default scope is ONLY the core brain** (brain-core plugin + own brain with
> the `core/` submodule). Additional suites — tool-domain plugins from your
> marketplace — are installed exclusively on explicit request; their checks only run
> when a suite is actually installed (otherwise `SKIP`, not red).

| # | Check | Green means |
|---|---|---|
| 1 | `gh auth status` + `ssh -T git@github.com` | access works, over SSH and not just HTTPS |
| 2 | `claude plugin list` | marketplace registered, `brain-core` installed AND enabled (suites noted as opt-in only) |
| 3 | plugin skills present | at least 1 core skill findable in the plugin cache (suite skills only with an installed suite) |
| 4 | output style | `caveman.md` comes from the brain-core plugin cache |
| 5 | SessionStart hooks | own brain exists and wires `core/helpers/session-bootup.sh`; the script runs |
| 6 | suite runtime deps | *only with an installed suite:* `node_modules` present — the plugin's npm install hook has fired |
| 7 | suite MCP startable | *only with an installed suite:* server manifest in the plugin cache + node >= 23.6 (a live round-trip needs the connected device) |
| 8 | leak check across the own tree | no foreign home paths or names landed in the own brain |
| 9 | `suite-check.py .` in the core checkout | the contract is verifiable on YOUR side, not only at the sender's |
| 10 | `ecosystem-sync.py` | your state is nameable (repo x commit x version) |
| 11 | shell start into the brain | marker `brain shell-start` in the shell profile — a bare `claude` in a fresh terminal starts IN the brain, not as a bare `$HOME` session |

Negative control (part of the acceptance, not of everyday use): deliberately break
one check (e.g. disable the plugin) — the verifier MUST turn red. A verifier that
can only go green is decoration.
