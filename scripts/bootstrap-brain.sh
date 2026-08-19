#!/usr/bin/env bash
# bootstrap-brain.sh — creates a NEW private brain from agent-brain/templates.
#
# Usage: scripts/bootstrap-brain.sh <target-dir> [core-repo-url]
#   target-dir       must not exist, or must be empty
#   core-repo-url    Default: https://github.com/arche-goah/agent-brain.git (public —
#                    use an SSH URL if your fork/marketplace setup needs keys anyway)
#
# What it does (and nothing else):
#   1. git init in the target
#   2. copy templates/ over (CLAUDE.md, .claude/settings.json, instance rules,
#      feedback.md, MEMORY.md seed as doc reference)
#   3. mount agent-brain as submodule `core/`
#   4. base structure (docs/maintenance, config, scripts, src, .claude/skills)
#   5. wire up the usage statusline (user scope, see below)
#   6. record state: REGISTRY.md + ecosystem pin (so handover-gate is green)
#   7. initial commit
# NO push, NO remote creation — that stays with the human.
#
# Step 5 is the ONLY touch outside $TARGET: it writes to ~/.claude/. It lives
# here because the statusline is ordered for every brain (effect-check E2 has
# warned since 2026-08-04 when it's missing), and a bootstrap that ships the
# helper but never wires it up produces exactly that warning.
# Disable with BOOTSTRAP_STATUSLINE=0.
set -euo pipefail

# Resolve the Python interpreter: the python.org installer on Windows ships ONLY
# `python`, and the Microsoft Store ships a `python3` STUB that resolves in PATH but
# does not run — so probe by RUNNING it, never with `command -v` (measured 2026-08-14:
# a colleague brain had no working `python3`, every reader below returned empty and
# brain-update.sh printed DONE without having done anything).
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python

CORE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:?Usage: bootstrap-brain.sh <target-dir> [core-repo-url]}"
CORE_URL="${2:-https://github.com/arche-goah/agent-brain.git}"

if [ -e "$TARGET" ] && [ -n "$(ls -A "$TARGET" 2>/dev/null)" ]; then
  echo "bootstrap-brain: $TARGET exists and is not empty — aborting (nothing overwritten)."
  exit 1
fi

# Check path length BEFORE the first write (Windows). Measured 2026-08-10 on
# Windows 11 / git 2.43: the longest path in the core is 80 characters
# (skills/last30days/scripts/lib/vendor/...), and core/ comes on top of that as a
# submodule. Without core.longpaths git fails at target+content > 260 with
# "Filename too long"; WITH longpaths the limit shifts to the GIT_DIR limit, which
# fails at a ~243-character target path with "'$GIT_DIR' too big". Both errors used
# to surface only MID-bootstrap, with a message that pointed at SSH — a false lead.
# On macOS/Linux (PATH_MAX 4096) the check is a no-op and does not run.
#
# The absolute path is ALWAYS computed, not just in the Windows branch: the
# submodule error message further down reports the length, and it must report the
# same number as this check. It used to print ${#TARGET} — the length of the
# PASSED-IN argument, which can be relative (review observation 2 on PR #37).
_parent="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd)"
_abs="$_parent/$(basename "$TARGET")"
_len=${#_abs}
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    # The WINDOWS path is what counts for the limit, not the POSIX path `pwd` returns
    # in Git Bash. The two can diverge widely because MSYS abbreviates mount points:
    # measured 2026-08-10, the same directory came out 111 characters in POSIX form
    # and 143 in Windows form — the check would have seen 32 characters too few and
    # waved through targets that are too long. `pwd -W` returns the Windows form.
    _wparent="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd -W 2>/dev/null || true)"
    if [ -n "$_wparent" ]; then
      _abs="$_wparent/$(basename "$TARGET")"
      _len=${#_abs}
    fi
    # Do NOT read core.longpaths with `git config --get`: that picks up the repo-local
    # config of the CALLING location. If the bootstrap runs from a repo that set the
    # switch locally, the check reports green — but the new repo inherits none of that
    # (review observation 1 on PR #37). What matters is what applies to a NEW repo:
    # global or system.
    _lp="$(git config --global --get core.longpaths 2>/dev/null || true)"
    [ "$_lp" = "true" ] || _lp="$(git config --system --get core.longpaths 2>/dev/null || true)"
    # 100-character reserve: 80 for the longest core path + core/ + .git/modules internals.
    if [ "$_len" -gt 200 ]; then
      echo "bootstrap-brain: target path is $_len characters long — that breaks even"
      echo "  the GIT_DIR limit with core.longpaths (measured: fails from ~243)."
      echo "  Pick a shorter target, e.g. ~/Projects/<name>-brain."
      exit 1
    fi
    if [ "$_len" -gt 160 ] && [ "$_lp" != "true" ]; then
      echo "bootstrap-brain: target path is $_len characters long and core.longpaths is off —"
      echo "  git would abort mid-bootstrap with 'Filename too long'."
      echo "  Fix: git config --global core.longpaths true   (Windows LongPaths alone"
      echo "  is NOT enough, git has its own switch), then start again."
      exit 1
    fi
    ;;
esac

mkdir -p "$TARGET"
cd "$TARGET"
git init -q

# 2. Templates
cp "$CORE_SRC/templates/CLAUDE.md" CLAUDE.md
mkdir -p .claude/rules .claude/skills docs/maintenance config scripts src
cp "$CORE_SRC/templates/settings.json" .claude/settings.json
cp "$CORE_SRC/templates/feedback.md" .claude/rules/feedback.md
cp "$CORE_SRC/templates/rules-instance/working-rules-instance.md" .claude/rules/
cp "$CORE_SRC/templates/rules-instance/intelligence-instance.md" .claude/rules/
cp "$CORE_SRC/templates/rules-instance/mechanism-rules.json" .claude/rules/
cp "$CORE_SRC/templates/leak-names.json" .claude/rules/leak-names.json
# MEMORY.md seed: Claude Code creates Auto-Memory itself — the seed documents the format.
mkdir -p docs/maintenance
cp "$CORE_SRC/templates/MEMORY.md" docs/maintenance/memory-seed-referenz.md
# Invariant register from day one (operator order 2026-08-19): a class needs a place
# where it stays open — without the register, the class-discipline rules reach a
# fresh brain as prose only.
cp "$CORE_SRC/templates/invariants.md" docs/maintenance/invariants.md

# .gitattributes BEFORE the first commit: Git for Windows defaults to core.autocrlf=true
# and then checks out CRLF. The workflow tool rejects a script with CR ("script contains
# control characters"), which means NO core workflow can start on Windows — measured
# 2026-08-04, fixed in the core with PR #10. A freshly bootstrapped brain ran into the
# same trap because only a .gitignore was written here.
cat > .gitattributes <<'EOF'
* text=auto eol=lf
*.png binary
*.jpg binary
*.pdf binary
EOF

cat > .gitignore <<'EOF'
.env
.env.*
.claude-state/
.DS_Store
__pycache__/
node_modules/
# Results of scheduled runs (helpers/run-record.sh) — runtime state of THIS machine,
# each one has its own scheduler.
docs/maintenance/scheduled-runs.tsv
EOF

cat > config/ecosystem.json <<EOF
{
  "_comment": "Which version of which suite is running here. Maintain with: python3 core/scripts/ecosystem-sync.py --write",
  "repos": {}
}
EOF

# dependencies.json is a required file (core-contract.json: required_files); in a brain
# it lives under config/ per CONVENTIONS section 9. Created empty means: "this brain
# pulls in nothing from outside" — an honest statement. Without the file, dep-lint
# --strict fails with exit 2, and the brain never passes its own handover-gate.
cat > config/dependencies.json <<'EOF'
{
  "manifest_version": 1,
  "requires_core": "*",
  "comment": [
    "External dependencies of this brain (CONVENTIONS.md section 9).",
    "Empty = this brain pulls in nothing from outside. Any source added",
    "later needs an entry here: kind (tool|vendored|workdir),",
    "url, pin, license, target, install."
  ],
  "dependencies": []
}
EOF

printf '# %s\n\nPrivate brain — bootstrapped from agent-brain/templates.\n' "$(basename "$TARGET")" > README.md
touch docs/maintenance/session-log.md docs/maintenance/decision-log.md

# 3. Core submodule
# Set longpaths repo-local before the submodule is pulled: the pre-check above lets
# targets up to 200 characters through, and there this switch decides whether the
# deep vendor paths of the core arrive intact. Repo-local is enough — the clone runs
# inside this repo. On macOS/Linux the option is a no-op, but harmless.
git config core.longpaths true

_sub_err="$(git submodule add "$CORE_URL" core 2>&1 >/dev/null)" || {
  case "$_sub_err" in
    *"too long"*|*"too big"*|*"Filename too long"*)
      echo "bootstrap-brain: submodule add failed on PATH LENGTH, not SSH:"
      echo "  $(printf '%s' "$_sub_err" | head -1)"
      echo "  target path is $_len characters (absolute). Pick a shorter target (e.g. ~/Projects/<name>-brain)."
      ;;
    *)
      echo "bootstrap-brain: submodule add failed — check SSH access to $CORE_URL."
      echo "  $(printf '%s' "$_sub_err" | head -2)"
      ;;
  esac
  exit 1
}

# 5. Usage statusline (user scope, idempotent, can be disabled)
if [ "${BOOTSTRAP_STATUSLINE:-1}" = "1" ] && [ -f core/scripts/install-statusline.sh ]; then
  sh core/scripts/install-statusline.sh || echo "bootstrap-brain: statusline not wired up — run 'sh core/scripts/install-statusline.sh' to catch up."
else
  echo "bootstrap-brain: statusline skipped (BOOTSTRAP_STATUSLINE=0 or installer missing)."
fi

# 6. Record state, so the new brain passes its own gate:
#    REGISTRY.md (skill-lint requires it, even with zero skills) and the
#    ecosystem pin (otherwise check 5 reports "core contract: pinned None").
"$PY" core/scripts/regen-skill-registry.py --skills .claude/skills >/dev/null 2>&1 ||
  echo "bootstrap-brain: REGISTRY.md not generated — run 'python3 core/scripts/regen-skill-registry.py --skills .claude/skills' to catch up."
"$PY" core/scripts/ecosystem-sync.py --write >/dev/null 2>&1 ||
  echo "bootstrap-brain: ecosystem.json not pinned — run 'python3 core/scripts/ecosystem-sync.py --write' to catch up."

# 7. Initial commit
git add -A
git commit -q -m "chore: bootstrap private brain from agent-brain templates"

echo "bootstrap-brain: OK — $TARGET is set up."
echo "Next steps: create a private GitHub repo, remote add, push (after agreement);"
echo "then start 'claude' in a terminal in $TARGET — marketplace/plugins are pulled from .claude/settings.json."
