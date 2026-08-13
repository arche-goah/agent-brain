# CONVENTIONS — agent-brain contract

> Lives in the core repo (`agent-brain`) and ships to every instance via the `core/` submodule.
> Written in English because it ships with the shared core (decision 2026-08-03: tools
> and core in English, instance docs and memory in the owner's language).
>
> **Scope:** this contract binds the core repo (`agent-brain`) and every tool suite built around it. It
> exists so that two people running separate private brains can exchange suites and rule
> changes without merge work. If a rule here is only true for one person's setup, it does
> not belong in this file.

## 0. The two layers

| Layer | Repo | Contains | Shared? |
|---|---|---|---|
| **Core** | `agent-brain` | working rules, hooks, linters, OS-level skills, settings template | yes, both pull |
| **Instance** | private brain (working directory) | `CLAUDE.md`, personal preferences, project docs, real configs, memory | never |
| **Suite** | one repo per domain | skills + MCP server + hooks for one tool domain | yes, via plugin |

The instance repo is the working directory and mounts the core as a git submodule.
Memory lives at `~/.claude/projects/<cwd-slug>/` — it follows the working directory, not
the repo, and is **never** committed to a shared repo.

## 1. Tool or instance — the deciding test

> **Does it run on a stranger's machine without editing a single file?**

Yes → tool, belongs in a suite or the core.
No → instance, stays private.

Consequences, non-negotiable:

- No real addresses, hostnames, device names, serials, MAC addresses, credentials, or
  keychain item names in a shared repo.
- Every configurable value ships as `*.example.*` only. The real file is gitignored and
  lives in the private layer; the tool reads its path from env or a CLI argument.
- Topology, port maps, VLAN schemes, universe numbers: config, never code. A suite that
  hardcodes one site's topology is not a suite.
- No behaviour that only makes sense for one owner's rig, venue, or client.

## 2. Suite repo shape

Every suite is a Claude Code plugin. Verified layout (2026-08-03, CLI 2.1.220):

```
<name>-suite/
  .claude-plugin/plugin.json   # {name, description, author}
  README.md                    # purpose, install, configuration, limits
  CHANGELOG.md
  skills/<skill-name>/SKILL.md
  commands/*.md                # optional
  agents/*.md                  # optional
  hooks/hooks.json             # optional
  .mcp.json                    # optional: the suite's MCP server
  mcp/                         # server source
  config/<name>.example.json
  .github/workflows/lint.yml
```

Rules:

- **No absolute paths anywhere.** Inside a plugin, paths resolve through
  `${CLAUDE_PLUGIN_ROOT}`. This is what makes a suite installable by someone else.
- The suite is installed with `claude plugin install <name>@<marketplace>`, never by
  hand-editing another person's `.mcp.json` or symlinking into `.claude/skills/`.
- A suite owns exactly one domain. New domain → new repo. Never add domain tools to the
  core or to a private brain.
- Third-party or proprietary content (vendored skill packs, licensed bundles) is
  **never** re-published inside a suite or the core. Reference it, do not copy it.

## 3. Naming and language

- Directories, skill names, repo names: `kebab-case`, lowercase, ASCII, English.
- MCP tool names: `<domain>_<verb>` (`mikrotik_port_role`, `gma3_store_cue`).
- Skill frontmatter `name` must equal its directory name.
- Skill `description` states the trigger, not just the topic — it is the only thing the
  model sees before loading the skill.
- Code, comments, docstrings, SKILL.md, README, commit messages: English.
- Instance docs and memory: the owner's language.

## 4. MCP servers

- Read-only by default. A write tool requires: preview of the change, explicit
  confirmation, mandatory readback of the result, and a journal entry.
- Destructive operations sit behind a denylist that the caller cannot bypass by
  rephrasing the request.
- No secret in the repo. Credentials come from the OS keychain or env at runtime.
- The server starts and answers with an empty config present — it must fail loudly with
  a usable message, not silently do nothing.
- Every tool is testable read-only against a device that does not exist yet (dry run or
  clear connection error).

## 5. Skills

- `skill-lint.py` (from the core) must pass: frontmatter valid, name matches directory,
  no dead `references/`/`scripts/` links, no trigger collision with a sibling skill,
  listing budget not exceeded.
- A skill that requires hardware states its precondition in the first section.
- A skill never writes outside the working directory it was invoked in.

## 6. Versioning and compatibility

> Enforced since 2026-08-03 by `suite-check.py` against `config/core-contract.json` —
> see §12. Before that this section was prose only, and it had already drifted: measured
> across four suites, none declared a core version, none had a changelog, none was tagged.

- Core and every suite carry semver tags and a `CHANGELOG.md`.
- Changelog format, one style everywhere: **newest entry first**, headings
  `## <version> — <date>` **without a `v` prefix** (tags keep theirs). Decided
  2026-08-10: the core wrote oldest-first with `v`, the suites newest-first without,
  and a suite release derailed when one habit was applied to the other repo
  (grandma3-suite PR #2); 4 of 5 repos already wrote prefix-less. §8 governs what an
  entry says (why + origin); this line governs where it goes.
- Each suite declares the core it was built against as `requires_core` in its
  `dependencies.json` (machine-checked). The README may repeat it for humans.
- Breaking a documented interface (tool name, config key, hook contract) is a major bump
  and gets a migration note in the changelog. Silent renames are not allowed.

## 7. CI (this is what keeps two setups comparable)

Every shared repo runs on pull request, blocking:

1. `skill-lint` — the checks in §5.
2. **Leak scan** — private IP ranges, MAC addresses, `.env`/key material, known real
   hostnames and site names. A hit fails the build. Documentation ranges are allowed on
   purpose (RFC 5737 `192.0.2.x`, RFC 7042 `00:00:5E:00:53:xx`), and any other exception
   must say in the scanner *why* it is a constant and not somebody's network.
3. `plugin.json` / `marketplace.json` parse + path check (no absolute paths).
4. `suite-check.py` — the contract itself (§12). A suite that fails it does not merge.
5. `dep-lint` — the dependency manifest resolves (§9).

Prose standards drift between two people within weeks. The CI is the actual contract;
this document only explains it.

## 8. How changes flow between two brains

Sort every change before writing it:

| Kind of change | Where it goes |
|---|---|
| Working rule, gate, hook, linter, OS skill | PR against `agent-brain` — both pull it |
| Domain tool or skill | PR against the suite repo — both reinstall the plugin |
| Personal preference, own rig, own clients, own projects | private layer only, never shared |

A rule commit carries **why** and **origin** in the message or in the file: which
incident, which decision, which date. A rule without its reason cannot be judged by the
other person and dies unmaintained.

Never merge a private layer into a shared repo, in either direction.

## 9. External dependencies

Measured 2026-08-03: eight skills in the brain point at a `tools/` directory that does
not exist. They are already dead here; on a second machine they would be dead from day
one, silently, mid-workflow. Undeclared external dependencies rot. Therefore:

- **Every repo carries a machine-readable `dependencies.json`.** Repo root, except where
  the repo's own layout rules forbid it — the brain keeps it in `config/`. One entry per
  external source: URL, pin, license, target path, install steps. **No entry, no
  dependency.**
- **Three kinds, because a check that cannot tell them apart gets ignored:**
  - `tool` — fetched from outside; needs `target` + `install`
  - `vendored` — third-party content already sitting in the repo; needs `distribution`
    (`reference-only` or `do-not-redistribute`)
  - `workdir` — scratch directory a skill creates itself; no source, may be absent
- **Every repo carries an installer** that executes the manifest. Dry-run by default,
  `--apply` to act. Onboarding is one command, never a manual rebuild.
- **CI check, blocking:** every `tools/`-style path referenced in a SKILL.md must appear
  in the manifest. A declared dependency that is *not installed* is reported, **not**
  failed — whether a checkout exists is a fact about the machine, not about the repo.
  The build only fails on what the repo itself got wrong.
- **Before sharing a repo**, the linter runs in `--strict` mode: every `unverified`
  license and URL must be resolved first. Unverified is an honest placeholder during
  work, never an export state.

Reference implementation in the brain: `config/dependencies.json`,
`scripts/dep-lint.py`, `scripts/dep-install.py`, `.github/workflows/lint.yml`.
- **Three classes, three treatments:**
  - *Proprietary / licence-restricted* — never enters a shared repo. The other side
    obtains it from its own vendor channel.
  - *Third-party, openly licensed* — referenced and installed from source, never
    re-published inside our repo. Keeps provenance visible and updates flowing.
  - *Our skill wrapping an external tool* — pinned in the manifest, and the skill states
    its precondition in the first section.

A skill whose external tool is missing must fail with a message naming the manifest
entry — not with a shell error deep inside a workflow.

## 10. The one rule an agent must follow without being told

New tool domain (a new MCP server, a new device family, a new application):
**create a new suite repo per §2.** Do not add it to the core. Do not add it to a private
brain. Register it in the shared marketplace so the other side installs it with one
command.

## 11. Where does this new thing go? (the placement gate)

Ask before writing the first file, not after. Answer in order — the first "yes" wins:

| Question | Then it goes to |
|---|---|
| Does it only make sense for one rig, venue, client, or show? | **private brain**, never shared |
| Does it belong to one tool domain (a device family, an application, a protocol stack)? | **that domain's suite** — or a **new suite repo** if none exists (§2, §10) |
| Is it a working rule, gate, hook, linter, or an OS-level skill that has nothing to do with a specific tool? | **the core (`agent-brain`)** |

Two consequences that are not optional:

- **A new capability never starts life inside a private brain.** Not "for now", not "until
  it settles". Something built in the private layer acquires that layer's assumptions —
  its paths, its addresses, its habits — and pulling it out later costs more than starting
  it right. Measured on this setup: every extraction so far (chataigne, show-tools,
  resolume) had to fix paths that only ever resolved inside the brain.
- **The core is an explicit include-list, not a leftover.** After every suite has moved
  out, what remains is core *plus* private instance. Deciding the core by subtraction ships
  somebody's private data.

## 12. Staying compatible — and how anyone can check it

Prose is not the contract; `suite-check.py` is. Sections 1–11 describe what it enforces.

- **`core-contract.json`** carries `contract_version` (semver) and the machine-readable
  requirements. Only a bump there changes what suites must satisfy, and every bump records
  **why**.
- **Every suite declares `requires_core` in its `dependencies.json`.** A major difference is
  breaking by definition — `>=1.0.0` does not accept a 2.x core.
- **`suite-check.py <path>`** runs from either side: from a brain over the suites it mounts,
  or inside a suite's own CI before anything merges. It checks required files, plugin and
  dependency manifests, that the leak scan actually runs in CI, and that no absolute home
  path is in a tracked file. ERROR blocks, WARN does not.
- **`ecosystem-sync.py` + `config/ecosystem.json`** answer "something changed somewhere":
  one file per brain recording which repo is pinned at which version and commit. Run it
  without arguments to see drift, with `--write` to record an intended state. It is
  instance data — each person keeps their own; the suites are the shared part.

**Changing an existing shared repo** therefore means: change it, keep `suite-check` green,
add a CHANGELOG line with the reason, tag if the interface moved, and let the other side
see it as one lockfile diff. If a change cannot keep `suite-check` green, it is a contract
change — bump `core-contract.json` with a reason and say so in the changelog. Silent
renames of a tool, a config key or a hook are not allowed (§6).

## 13. Operations: syncing two independent brains

Two people, two private brains, shared suites. The goal is that no sync ever produces a
conflict a human must resolve by hand — reached structurally, not through care.

**Four rules from which conflict-freedom follows:**

1. **Every file has exactly one home repo** — the placement gate in §11 decides it, first
   "yes" wins. Corollary restated: a new capability never starts life inside a private brain.
2. **No file travels over two channels.** The core is consumed twice — its `skills/`,
   `agents/`, `output-styles/` as a plugin, its `rules/`, `scripts/`, `helpers/`,
   `templates/`, contract files as the `core/` submodule — and each file belongs to exactly
   one of the two. Two copies of the same truth are guaranteed to drift (measured: the
   leak-scan fix existed in one of four copies).
3. **Shared material is never edited locally.** Suite changes happen in the suite repo
   (branch + PR), never in the installed plugin cache and never in a brain-side copy. The
   cache is read-only delivery; the dev loop is `claude --plugin-dir <repo>`.
   **Core changes have the same shape, and one word needed defining** (operator decision
   2026-08-10, full-audit finding E1 — three artifacts contradicted each other on where
   core work happens): "never edit core directly" forbids editing the **consumed state**
   — the detached-HEAD pin an instance runs on, or main — never the checkout as such.
   Core work happens on a **feature branch in any full core checkout**, and an
   instance's `core/` submodule IS such a checkout (the Windows brain's PRs since #14
   were all cut there; a standalone clone works the same). Mechanical half:
   `helpers/file-guard.cjs` blocks an agent's Edit/Write into a core checkout (identified by its plugin manifest name `brain-core`)
   sitting on the pin or on main and prints the branch command; a feature branch passes.
   The checkout is identified by its own plugin manifest, not by path, so the guard
   travels to every instance without configuration.
   **Where that checkout lives is not a free choice: `~/Projects/<repo-name>`**, the repo's
   own name, no abbreviation. `ecosystem.json` records the same path, so `handover-gate`
   can find it. Ad-hoc short paths (`C:\g3` for `grandma3-suite`) were invented on Windows
   to dodge `Filename too long` — that cause is gone since 1.3.5 (`core.longpaths`, checked
   at bootstrap and in the onboarding preflight), and the abbreviation now only costs: the
   entry stops matching its repo, and the next person cannot guess it. One name, one place.
4. **Instance data is never shared.** Memory, feedback rules, `ecosystem.json`, rig and
   show data stay per person. There is no "merge" of two memories — separate histories are
   the normal case, not a defect.

**The sync beat.** Pulling (each side for itself, weekly is enough, never on a show day):
`bash core/scripts/brain-update.sh` — refreshes the marketplaces, every enabled plugin
(cache provenance verified against the pin), the `core/` submodule onto the pinned tag,
`ecosystem.json`. Not `git submodule update --remote core`: that tracks `main`, not the
released pin. Giving:
branch → CI green → PR → merge → **tag → marketplace pin**. Only the pin makes a change
visible to the other side — "I pushed" never means "something changed for you"; the
receiver stays in control.

**The one hard gate.** On personal GitHub accounts (no org) there is no enforceable merge
gate; CI reports but cannot block. Therefore `handover-gate.sh`, run locally **from the
submodule** (same file on both sides), is *the* mandatory check before anything is handed
over. Skipping it is not a shortcut, it is removing the only gate that exists.

**Breaking changes** follow §12: major bump of `contract_version` with a recorded reason;
non-conforming suites fail at `suite-check.py`, at the gate, not at the colleague's desk.
Silent renames stay forbidden (§6); the old name lives one version as a deprecated alias.
The way back is always open: marketplace pin to the previous tag, submodule to the
previous SHA — rollback is a one-liner because both are pinned.

**Known residual risks and their standing answers:** both build the same tool
independently → read the drift report and suite CHANGELOGs before starting work; skill
name collision → plugin skills are namespaced, local `.claude/skills/` hold instance
skills only; a core rule drifts → core rules come from the submodule, local additions go
into the instance rule file the guard loads; update breaks near a show → update window is
never on a show day, rollback per pin; private-repo auto-refresh fails over HTTPS → use
SSH remotes with a loaded ssh-agent, or run marketplace update manually.
