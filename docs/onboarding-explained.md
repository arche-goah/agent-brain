# Onboarding explained — the picture behind the steps

`ONBOARDING.md` is the procedure: run a command, measure, move on. This page is the
background a newcomer needs to understand WHAT those steps build and WHY they are in that
order. Read it once before the procedure, or whenever a step makes no sense. Nothing here
has to be executed.

Throughout this page, `your-org` is the GitHub organization that hosts your marketplace
and your team's private repos.

## 1. The three layers

```
   +--------------------------------------------------------+
   |  YOUR BRAIN (private, your working directory)          |
   |  CLAUDE.md - your preferences - your project docs      |
   |  your real configs - your memory                       |
   |                                                        |
   |    core/  -->  agent-brain  (shared, git submodule)    |
   |                rules, hooks, linters, OS skills        |
   +--------------------------------------------------------+
                         ^  installed as plugins
                         |
   +---------------------+----------------------------------+
   |  SUITES (one repo per tool domain)                     |
   |  e.g. a lighting-desk suite, a video-server suite,     |
   |  your own future suites                                |
   |  = skills + MCP servers + example configs, generic     |
   +--------------------------------------------------------+
```

| Layer | Repo | Content | Shared? |
|---|---|---|---|
| **Core** | `agent-brain` (plugin name: `brain-core`) | working rules, hooks, linters, operating-system skills, settings template | yes, every brain draws from it |
| **Instance** | your private brain | `CLAUDE.md`, preferences, project docs, real configs, memory | never |
| **Suite** | one repo per domain | skills + MCP servers + hooks for ONE tool field | yes, as a plugin |

Your private brain is at the same time your **working directory** — the folder you start
`claude` in. The core reaches it twice: as the `brain-core` plugin (skills, hooks, output
style) and as the `core/` git submodule (the rule files your `CLAUDE.md` imports, the
scripts). Suites are installed as Claude Code plugins, one per tool domain, and only when
you need them.

The dividing line between the layers is one question: **does it run on a stranger's machine
without editing a file?** Then it is a tool and may be shared (core or suite). Does it name
your addresses, devices, clients, preferences or show files? Then it is instance data and
stays in your brain.

## 2. The four carriers of behaviour

Claude Code does not "read the repo". Behaviour reaches a session reliably through exactly
four places:

| Carrier | What | When it is loaded |
|---|---|---|
| `CLAUDE.md` in the working directory (plus the files it `@`-imports) | rules, stack, conventions | every session, automatically |
| skills (`SKILL.md` in a plugin or in `.claude/skills/`) | abilities with a trigger description | name + description always, the body on demand |
| hooks (the plugin's `hooks/hooks.json`, your `.claude/settings.json`) | automation: session start, guards, notifications | mechanically, independent of the model |
| MCP server `instructions` | the tool's own safety notice | at session start |

**A consequence worth knowing:** a `CLAUDE.md` in a SUBFOLDER is not loaded at the start; it
is loaded only once Claude reads files in that subfolder. If an agent clones someone else's
repo, it sees that repo's safety rules at the earliest then — possibly after it has already
run the first file. That is why, for tools, the order of strength is:

1. **Enforced** — server-side guards (`confirm=true`, mandatory readback), permissions on the
   target system, a PreToolUse hook. Survives every model and every lapse of attention.
2. **Guaranteed to be seen** — MCP `instructions`, tool names, tool descriptions.
3. **Probably seen** — the README head, a `CLAUDE.md` in the repo root.
4. **Maybe** — everything deeper.

When behaviour really has to arrive, it belongs on level 1 or 2. A rule line in a Markdown
file is level 3-4. **Being in the context is not the same as being followed** — which is why
this core turns its important rules into hooks and checks instead of more prose.

## 3. Windows in depth

`ONBOARDING.md` names the Windows traps in one line each. Here is the reasoning, so you can
recognise them when they bite. Commands change quickly; where one no longer matches,
`code.claude.com/docs` is right and this page is stale.

**Native or WSL?** Native Windows needs nothing extra (Git for Windows recommended). WSL 2
adds Linux toolchains and sandboxing, but also a network boundary between Claude and the
programs on your Windows desktop. If your tools (show software, local apps that MCP servers
talk to) run natively on Windows, start native; WSL can be added later at any time.

**Terminal.** Windows Terminal is the comfortable host; PowerShell 7
(`winget install Microsoft.PowerShell`) is nicer than the built-in PowerShell 5, but
optional.

**Where your projects live.**

- A short path. Git has a second, deeper limit for the `.git` directory itself
  (`'$GIT_DIR' too big`, from roughly 240 characters of target path), so do not nest deeply.
- **Not** inside a OneDrive-synchronised folder. OneDrive moves and locks files in the
  background; that breaks git repositories and file watchers. It is the most common Windows
  trap with a setup like this.
- **On the internal disk, not on an external SSD or stick.** Removable media are usually
  exFAT, where git refuses to work with `detected dubious ownership`. It can be repaired per
  repo (`git config --global --add safe.directory <path>`), but you then carry that exception
  for every repo — and the drive letter disappears whenever the medium is not plugged in, so
  every configured path points nowhere.

**Git for Windows.** It gives Claude Code its Bash tool (through Git Bash). Without it,
Claude Code falls back to PowerShell — that works, but the scripts in the core and the
suites are written for bash. Configure it once:

```powershell
git config --global user.name "Your Name"
git config --global user.email "<your-id>+<your-login>@users.noreply.github.com"
git config --global init.defaultBranch main
git config --global core.autocrlf false
git config --global core.longpaths true
```

- The GitHub **noreply address** keeps your real address out of every public commit; with
  GitHub's "block command line pushes that expose my email" switched on, a push with a real
  address is refused.
- `core.autocrlf false` is deliberate: the shared repos contain shell scripts that need LF
  line endings; Windows line endings would make them unusable.
- `core.longpaths true` is the line most often missing. Windows has its own "LongPathsEnabled"
  switch, but **git ignores it and brings its own**. Without it, a clone of a deep repo breaks
  off in the middle with `Filename too long`. (Measured once, 2026-08-10: on a machine with
  `LongPathsEnabled` = 1, a 193-character target path still failed; with the git switch the
  same clone went through.)

**Python.** When installing, tick **"Add python.exe to PATH"** — the most common mistake.
If `python` opens the Microsoft Store instead of printing a version, PATH is not set: run the
installer again with the box ticked. On Windows, `python3` can be that Store stub even when
`python` works; the core's scripts are written to cope with it.

**Claude Code.** In PowerShell: `irm https://claude.ai/install.ps1 | iex`. (In CMD the
command differs — the error `'irm' is not recognized` tells you that you are in the wrong
terminal.) The WinGet package (`winget install Anthropic.ClaudeCode`) does not update itself;
you would run `winget upgrade Anthropic.ClaudeCode` by hand. The native installer keeps
itself current. Check with `claude --version` and `claude doctor` — the latter is a
diagnosis without starting a session and your first tool for any later problem. If Claude
Code does not find Git Bash, point it there in `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_GIT_BASH_PATH": "C:\\Program Files\\Git\\bin\\bash.exe"
  }
}
```

**SSH key by hand.** `gh auth login` with SSH as the protocol creates and uploads the key for
you. If you create it yourself (`ssh-keygen`), starting the `ssh-agent` service needs an
administrator PowerShell (a normal one ends with `Access is denied`):

```powershell
Set-Service ssh-agent -StartupType Automatic
Start-Service ssh-agent
```

The service is not a criterion of its own as long as your key has no passphrase — what
counts is the access (`ssh -T git@github.com`), not the agent. Git Bash never sees that
service (named pipe versus Unix socket); an empty `SSH_AUTH_SOCK` there is not an error.

**A first try before the brain.** In an empty folder (`git init`, then `claude`) try `/help`,
`/context` (what is loaded right now) and `/config`, and ask Claude to create a small file and
delete it again — you will see how the permission prompts work. Claude Code works **in the
current folder** and asks before actions until you allow them.

## 4. Glossary

**Agent / subagent** — a second Claude instance that takes over a bounded subtask and returns
a result. Useful for independent work, expensive in tokens. It is a concurrent writer: it can
touch the same files you do.

**Working directory (cwd)** — the folder you start `claude` in. It decides which rules,
skills and memory are loaded. Here: your private brain.

**agent-brain (core repo) / brain-core (plugin)** — the shared core: working rules, hooks,
linters, operating-system skills, settings template. Mounted as the `core/` git submodule in
your brain; its plugin is called `brain-core`, so skill references read `brain-core:<name>`.

**Brain (private)** — your working directory plus your instance data: `CLAUDE.md`,
preferences, project docs, real configs, memory. Never shared.

**CLAUDE.md** — the file in the working directory that is loaded automatically in every
session. A `CLAUDE.md` in a subfolder loads only when files there are read (section 2).

**Gate** — a mandatory condition before an action (for example "show the preview and get a
confirmation before writing"). The opposite of a good intention: it is wired into the tool.

**Hook** — a script the environment runs mechanically on an event (session start, before or
after a tool call, session end). It runs whether or not the model thinks of it — the most
reliable place for automation.

**Instance** — everything that only holds for you: real addresses, device names, clients,
preferences, show files. Stays private. The opposite of a tool.

**Leak scan** — the automatic check before sharing: private IP ranges, MAC addresses, keys,
real host names. If it finds something, the build fails.

**Marketplace** — a git repo with a `marketplace.json` that lists plugins and pins their
released tags. It can be private. It lets you install a suite with one command instead of by
hand.

**MCP (Model Context Protocol)** — the standard through which Claude gets real tools. An
**MCP server** is a program that provides tools ("read the status of device X", "set port Y").
At session start only the **tool names** and the server's **`instructions`** are guaranteed
to load — that is where the most important things belong.

**Memory** — the long-term memory: one file per fact under `~/.claude/projects/<slug>/memory/`,
plus an index `MEMORY.md` that is loaded every session (keep it within 200 lines / 25 KB). It
belongs to the working directory, not to the repo.

**Plugin** — the packaging that makes a suite (or the core) installable: a folder with
`.claude-plugin/plugin.json` and optionally `skills/`, `agents/`, `hooks/`, `.mcp.json`. Paths
inside resolve through `${CLAUDE_PLUGIN_ROOT}`, which is why it works on someone else's
machine.

**Preview / confirm / readback** — the write chain for real hardware: first show the planned
change, then an explicit confirmation, then read the result back from the device. Without the
readback a change is not proven, only sent.

**Role sync** — a change only really exists once it is not only live on the device but also in
the versioned configuration. Otherwise the next reset undoes it.

**Skill** — a folder with `SKILL.md`: instructions Claude loads on a matching trigger. The
`description` is decisive — it is the only part the model sees in advance, and it has to name
the trigger, not just the topic.

**Suite** — one repo per tool domain: skills + MCP servers + example configs. Generic,
shareable, installable as a plugin.

**Tool** — anything that runs on a stranger's machine without a file being edited. May be
shared. The opposite of instance.
