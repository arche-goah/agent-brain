#!/usr/bin/env bash
# covers: bootstrap-brain
#
# Fixture for scripts/bootstrap-brain.sh, run for real against a throwaway local core repo. A
# fresh-brain trial on 2026-10-31 (a stranger's setup against 2.0.5) found two defects it proves gone:
#   1. the core submodule sat at untagged main (v2.0.5-30-g317916c). Now the newest vX.Y.Z is
#      checked out — by VERSION order (v1.10.0 over v1.9.0), never a pre-release — BOOTSTRAP_CORE_REF
#      wins, an unknown ref aborts, and a core without a release tag stays on its branch and says so;
#   2. 8 of the 16 template data files a core helper reads were not copied, so the first session start
#      was red. Now template-drift.py names none after a bootstrap (and does name one taken away).
# Isolation: HOME, the git config (global and system), gh (a stub that is not logged in) and the
# statusline are the fixture's own; the core is a local repo, nothing leaves the machine.
#
# Usage: bash scripts/test-bootstrap-brain.sh   (exit 0 = all cases pass)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BS="$HERE/bootstrap-brain.sh"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
# Paths cross into git and python as DATA (the core URL, GIT_CONFIG_GLOBAL): stated natively (OS-3).
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

mkdir -p "$T/home" "$T/bin"
printf '#!/bin/sh\nexit 1\n' > "$T/bin/gh"; chmod +x "$T/bin/gh"
printf '[user]\n\tname = t\n\temail = t@example.org\n[protocol "file"]\n\tallow = always\n[core]\n\tlongpaths = true\n[init]\n\tdefaultBranch = main\n' > "$T/gitconfig"
export HOME="$T/home" GIT_CONFIG_GLOBAL="$(native "$T/gitconfig")" GIT_CONFIG_NOSYSTEM=1 BOOTSTRAP_STATUSLINE=0 PATH="$T/bin:$PATH"
unset BOOTSTRAP_CORE_REF

# A core with the real templates and helpers (the data-file list is read from them), tagged
# v1.0.0, v1.9.0, v1.10.0, a pre-release v1.11.0-beta.1, and one unreleased commit on top.
make_core() { # make_core <dir> <tag>...
  local c="$1" v; shift
  mkdir -p "$c"; cp -r "$ROOT/templates" "$ROOT/helpers" "$c/"
  git -C "$c" init -q; git -C "$c" add -A; git -C "$c" commit -qm base
  for v in "$@"; do echo "$v" > "$c/VERSION"; git -C "$c" add -A; git -C "$c" commit -qm "$v"; git -C "$c" tag "$v"; done
  echo unreleased > "$c/VERSION"; git -C "$c" add -A; git -C "$c" commit -qm unreleased
}
C="$T/core"; make_core "$C" v1.0.0 v1.9.0 v1.10.0 v1.11.0-beta.1
boot() { # boot <target> [VAR=value]... -> $out, $rc
  out="$(cd "$T" && env "${@:2}" bash "$BS" "$T/$1" "$(native "$C")" 2>&1)"; rc=$?
}
at() { git -C "$T/$1/core" rev-parse HEAD; }
want() { git -C "$C" rev-parse "$1^{commit}"; }

# 1 default: the newest release tag by version order, recorded in the brain's first commit
boot b1
case "$rc:$out" in 0:*"core at v1.10.0 ("*"the newest release tag"*) ok "default: the newest release tag is named";; *) bad "default: rc=$rc out='$out'";; esac
[ "$(at b1)" = "$(want v1.10.0)" ] && ok "default: core/ checked out at v1.10.0 (not v1.9.0, not the beta, not main)" \
  || bad "default: core/ at $(git -C "$T/b1/core" describe --tags --always)"
link=$(git -C "$T/b1" ls-tree HEAD core); link=${link#* commit }; link=${link%%[[:space:]]*}
[ "$link" = "$(want v1.10.0)" ] && ok "default: the brain's first commit pins the tag's commit" || bad "default: gitlink $link"

# 2 the template data files: after bootstrap the session start's data check names none
drift() { "$PY" "$ROOT/scripts/template-drift.py" --repo "$(native "$T/b1")" \
  --rules-template "$(native "$T/b1/core/templates/rules-instance")" --helpers "$(native "$T/b1/core/helpers")" 2>&1; }
d=$(drift)
case "$d" in *"data file(s) of core/templates"*) bad "data files missing after bootstrap: '$d'";; *) ok "every helper-read template data file is in .claude/rules/";; esac
[ -f "$T/b1/.claude/rules/skill-gate.json" ] && [ -f "$T/b1/.claude/rules/operator-only.json" ] && [ -f "$T/b1/.claude/rules/decision-review.json" ] \
  && ok "the trial's missing files and the script-read files are there" || bad "rules: $(ls "$T/b1/.claude/rules")"
rm -f "$T/b1/.claude/rules/skill-gate.json"; d=$(drift)
case "$d" in *"data file(s) of core/templates"*skill-gate.json*) ok "control: a file taken away is named";; *) bad "control: not named: '$d'";; esac

# 3 BOOTSTRAP_CORE_REF wins, and says so
boot b2 BOOTSTRAP_CORE_REF=v1.0.0
[ "$rc" = 0 ] && [ "$(at b2)" = "$(want v1.0.0)" ] && ok "BOOTSTRAP_CORE_REF=v1.0.0: core/ at v1.0.0" || bad "override: rc=$rc out='$out'"
case "$out" in *"core at v1.0.0"*"BOOTSTRAP_CORE_REF"*) ok "the override is named";; *) bad "override not named: '$out'";; esac

# 4 an unknown ref aborts instead of leaving core/ on main
boot b3 BOOTSTRAP_CORE_REF=v9.9.9
case "$rc:$out" in 1:*"cannot be checked out"*) ok "unknown BOOTSTRAP_CORE_REF: aborts (exit 1)";; *) bad "unknown ref: rc=$rc out='$out'";; esac

# 5 no release tag at all (only a pre-release): stays on the branch and says so, exit 0
C="$T/core-untagged"; make_core "$C" v2.0.0-rc.1
boot b4
[ "$rc" = 0 ] && [ "$(at b4)" = "$(git -C "$C" rev-parse HEAD)" ] && ok "no release tag: core/ stays on its branch, exit 0" || bad "untagged: rc=$rc out='$out'"
case "$out" in *"no release tag (vX.Y.Z)"*) ok "no release tag: said so";; *) bad "untagged not said: '$out'";; esac

[ "$fail" = 0 ] && echo "bootstrap-brain: all cases pass" || { echo "bootstrap-brain: FAILURES"; exit 1; }
