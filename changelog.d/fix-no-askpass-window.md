- **No sign-in window from a background git call** (test: T1) (level: writer; higher: design — each call sets its own
  environment, the guard keeps the class closed; debt: `scripts/preflight.ps1` keeps GIT_TERMINAL_PROMPT only, Windows
  prompts through the credential manager, not askpass). Measured on the macOS instance 2026-11-03: the session ran in an
  editor's terminal whose `GIT_ASKPASS` points at the editor's askpass script; a fixture's `git ls-remote` against a
  made-up remote opened the editor's GitHub sign-in window in front of the operator. `GIT_TERMINAL_PROMPT=0` does not
  stop an askpass program; `brain-update.sh` and the session start already set `GIT_ASKPASS=true SSH_ASKPASS=true`.
  - `scripts/preflight.sh`, `helpers/session-pull.sh`, `helpers/git-hooks/pre-commit`: the same three variables.
  - `scripts/git_sandbox.py`: every fixture process runs with no prompt and no askpass.
  - Class guard in `test-git-sandbox.sh`: every `GIT_TERMINAL_PROMPT=0` line in helpers/ and scripts/ also sets
    `GIT_ASKPASS` (three hits on the old main). Fixture +2.
