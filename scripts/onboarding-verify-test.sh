#!/usr/bin/env bash
# covers: onboarding-verify (where the report lands; check 1 access, check 5 bootup hook, check 12)
#
# The verifier writes a report INTO the brain it checks. Until 2026-09-13 that meant the
# brain ROOT — a file the root whitelist (rules/working-rules.md) has no seat for, so
# every run created what the next session had to move or delete (measured three times
# on one instance). The report is an artifact and lands in docs/maintenance/, named by
# host and date. This fixture runs the REAL script against throwaway brains; the eleven
# checks themselves go red there (no plugin, no gh) — fine, only the report's PLACE is
# under test, so the verifier's exit code is ignored. Both directions: a recognised
# brain must keep its root clean, and no brain at all must still leave a report.
#
# Run: bash scripts/onboarding-verify-test.sh    Exit 0 = all green.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
V="$HERE/onboarding-verify.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok()  { echo "  OK   $*"; }
bad() { echo "  FAIL $*"; fails=$((fails + 1)); }

NAME="onboarding-report-${HOSTNAME:-$(hostname)}-$(date +%F).txt"
make_brain() { mkdir -p "$1/core" "$1/.claude"; printf '{}\n' > "$1/.claude/settings.json"; }

# Isolation: a HOME without Projects/*-brain, no BRAIN_DIR, an empty plugin cache — the
# script may find only what the fixture put in front of it, never the real brain.
mkdir -p "$T/home" "$T/cfg" "$T/elsewhere"
run() { # $1 working directory, rest = verifier arguments
  local d="$1"; shift
  ( cd "$d" && HOME="$T/home" CLAUDE_CONFIG_DIR="$T/cfg" env -u BRAIN_DIR bash "$V" "$@" >/dev/null 2>&1 )
}

echo "onboarding-verify — report placement:"

# --- 1 the documented call: brain path as argument, run from elsewhere ---------------
B1="$T/brain1"; make_brain "$B1"
run "$T/elsewhere" "$B1"
[ -e "$B1/onboarding-report.txt" ] && bad "argument: brain root got onboarding-report.txt" \
  || ok "argument: brain root stays clean"
[ -f "$B1/docs/maintenance/$NAME" ] && ok "argument: report at docs/maintenance/$NAME" \
  || bad "argument: report missing under docs/maintenance"

# --- 2 --out wins, and the default is not written beside it -------------------------
B2="$T/brain2"; make_brain "$B2"
run "$T/elsewhere" "$B2" --out "$T/custom/report.txt"
[ -f "$T/custom/report.txt" ] && ok "--out: report at the given path (directory created)" \
  || bad "--out: ignored"
[ -e "$B2/docs/maintenance/$NAME" ] && bad "--out: default file written anyway" \
  || ok "--out: default suppressed"
[ -e "$B2/onboarding-report.txt" ] && bad "--out: brain root got onboarding-report.txt" \
  || ok "--out: brain root stays clean"

# --- 3 the incident path: no argument, standing INSIDE a brain outside ~/Projects ----
B3="$T/brain3"; make_brain "$B3"
run "$B3"
[ -e "$B3/onboarding-report.txt" ] && bad "cwd-is-brain: root got onboarding-report.txt" \
  || ok "cwd-is-brain: root stays clean"
[ -e "$B3/$NAME" ] && bad "cwd-is-brain: report in the root under the new name" \
  || ok "cwd-is-brain: nothing in the root under the new name either"
[ -f "$B3/docs/maintenance/$NAME" ] && ok "cwd-is-brain: report under docs/maintenance" \
  || bad "cwd-is-brain: report missing under docs/maintenance"

# --- 4 no brain anywhere: the working directory keeps the report (unchanged) --------
mkdir -p "$T/nowhere"
run "$T/nowhere"
[ -f "$T/nowhere/$NAME" ] && ok "no brain: report in the working directory" \
  || bad "no brain: report not in the working directory"

# --- 5 a verify run is no session: the shared-memory cursor stays where it was -------
# (a Windows instance 2026-09-30: check 5 ran the bootup, which moved the cursor past
# entries no session had shown.) The stub bootup advances the cursor like the real one.
B5="$T/brain5"; make_brain "$B5"; mkdir -p "$B5/core/helpers" "$B5/.claude-state"
printf '{"hooks":{"SessionStart":[{"hooks":[{"command":"core/helpers/session-bootup.sh"}]}]}}\n' > "$B5/.claude/settings.json"
printf '%s\n' '#!/usr/bin/env bash' \
  'echo "=== BRAIN BOOTUP CHECK ==="' \
  'echo "{\"lastSeenSha\": \"new\"}" > "${SHARED_MEMORY_STATE:-.claude-state/shared-memory-state.json}"' \
  > "$B5/core/helpers/session-bootup.sh"
echo '{"lastSeenSha": "old"}' > "$B5/.claude-state/shared-memory-state.json"
run "$B5" "$B5"
grep -q '"old"' "$B5/.claude-state/shared-memory-state.json" && ok "verify: shared-memory cursor untouched" \
  || bad "verify: shared-memory cursor advanced ($(cat "$B5/.claude-state/shared-memory-state.json"))"
grep -q "5.*Brain+hooks.*appears" "$B5/docs/maintenance/$NAME" 2>/dev/null && ok "verify: bootup still ran (check 5 sees its output)" \
  || bad "verify: check 5 did not see the bootup output"

# --- 6 a config dir with a SPACE (Windows profile "First Last"): an installed suite is
# found, not split into "/.../First" + "Last/..." and reported MISSING (os-traps OS-10).
SP="$T/cfg space"; B6="$T/brain6"; make_brain "$B6"
mkdir -p "$SP/plugins/cache/mkt/brain-core/1.0.0/skills/a" "$SP/plugins/cache/mkt/suite-x/1.0.0/skills/b"
touch "$SP/plugins/cache/mkt/brain-core/1.0.0/skills/a/SKILL.md" "$SP/plugins/cache/mkt/suite-x/1.0.0/skills/b/SKILL.md"
printf '{}
' > "$SP/plugins/cache/mkt/suite-x/1.0.0/.mcp.json"
( cd "$B6" && HOME="$T/home" CLAUDE_CONFIG_DIR="$SP" env -u BRAIN_DIR bash "$V" "$B6" >/dev/null 2>&1 )
grep -q "3 Plugin skills — core=present, suites=present (suite-x )" "$B6/docs/maintenance/$NAME" 2>/dev/null   && ok "space in path: suite found by its name"   || bad "space in path: $(grep ' 3 Plugin skills' "$B6/docs/maintenance/$NAME" 2>/dev/null)"

# --- 7 check 12: shared-memory self — skip without a checkout, red unset, green set ----
B7="$T/brain7"; make_brain "$B7"
( cd "$B7" && HOME="$T/home" CLAUDE_CONFIG_DIR="$T/cfg" env -u BRAIN_DIR -u SHARED_MEMORY_SELF \
    SHARED_MEMORY_REPO="$T/no-such-repo" bash "$V" "$B7" >/dev/null 2>&1 )
grep -q "^SKIP 12 Shared-memory self" "$B7/docs/maintenance/$NAME" && ok "self: no checkout, SKIP" \
  || bad "self: no checkout did not SKIP"
mkdir -p "$T/smr"
( cd "$B7" && HOME="$T/home" CLAUDE_CONFIG_DIR="$T/cfg" env -u BRAIN_DIR -u SHARED_MEMORY_SELF \
    SHARED_MEMORY_REPO="$T/smr" bash "$V" "$B7" >/dev/null 2>&1 )
grep -q "^FAIL 12 Shared-memory self" "$B7/docs/maintenance/$NAME" && ok "self: unset, FAIL" \
  || bad "self: unset did not FAIL"
printf '{"env":{"SHARED_MEMORY_SELF":"me-test"}}\n' > "$B7/.claude/settings.json"
( cd "$B7" && HOME="$T/home" CLAUDE_CONFIG_DIR="$T/cfg" env -u BRAIN_DIR -u SHARED_MEMORY_SELF \
    SHARED_MEMORY_REPO="$T/smr" bash "$V" "$B7" >/dev/null 2>&1 )
grep -q "^OK   12 Shared-memory self — SHARED_MEMORY_SELF=me-test" "$B7/docs/maintenance/$NAME" && ok "self: set in settings env, OK" \
  || bad "self: set in settings env not seen"

# Stubs for gh, ssh and claude: checks 1 and 5 below must not depend on the runner's own logins.
stubs() { # stubs <dir> <gh exit code> <what ssh says>
  mkdir -p "$1"
  printf '#!/bin/sh\nexit %s\n' "$2" > "$1/gh"
  printf '#!/bin/sh\necho "%s"\nexit 1\n' "$3" > "$1/ssh"
  printf '#!/bin/sh\nexit 1\n' > "$1/claude"
  chmod +x "$1/gh" "$1/ssh" "$1/claude"
}
SSH_OK="Hi fixture! You've successfully authenticated, but GitHub does not provide shell access."
SSH_RED="git@github.com: Permission denied (publickey)."

# --- 8 check 1: the gh login is mandatory, missing SSH is only a warning (the preflight's rule;
# fresh-brain trial 2026-10-31: HTTPS through gh, as ONBOARDING.md allows, read FAIL here) -------
access() { # access <stub dir> -> the report's check-1 line
  local b="$T/brain-access"; rm -rf "$b"; make_brain "$b"
  ( cd "$b" && PATH="$1:$PATH" HOME="$T/home" CLAUDE_CONFIG_DIR="$T/cfg" env -u BRAIN_DIR bash "$V" "$b" >/dev/null 2>&1 )
  grep -a ' 1 Access' "$b/docs/maintenance/$NAME"
}
stubs "$T/bin-both" 0 "$SSH_OK"; stubs "$T/bin-https" 0 "$SSH_RED"; stubs "$T/bin-ssh" 1 "$SSH_OK"
line=$(access "$T/bin-both")
case "$line" in "OK    1 Access — gh=ok, ssh=ok"*) ok "access: gh and SSH, OK";; *) bad "access: gh and SSH: '$line'";; esac
line=$(access "$T/bin-https")
case "$line" in "WARN  1 Access — gh=ok, ssh=red"*) ok "access: gh without SSH, WARN (not FAIL)";; *) bad "access: gh without SSH: '$line'";; esac
line=$(access "$T/bin-ssh")
case "$line" in "FAIL  1 Access — gh=red, ssh=ok"*) ok "access: SSH without the gh login, FAIL";; *) bad "access: SSH without gh: '$line'";; esac

# --- 9 check 5: the bootup hook shipped by the brain-core plugin (hooks/hooks.json, since 2.0.4)
# counts; a brain's settings.json no longer names it (fresh-brain trial 2026-10-31: FAIL forever).
# installPath is DATA for python, so it is stated natively (docs/os-traps.md OS-3).
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
plugin_brain() { # plugin_brain <brain> <config dir> <install ships hooks/hooks.json: yes|no>
  local inst="$2/plugins/cache/fx/brain-core/9.9.9"
  make_brain "$1"; mkdir -p "$1/core/helpers" "$inst"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "=== BRAIN BOOTUP CHECK ==="' > "$1/core/helpers/session-bootup.sh"
  printf '{"enabledPlugins": {"brain-core@fx": true}}\n' > "$1/.claude/settings.json"
  if [ "$3" = yes ]; then mkdir -p "$inst/hooks"; cp "$HERE/../hooks/hooks.json" "$inst/hooks/"; fi
  printf '{"plugins": {"brain-core@fx": [{"scope": "user", "installPath": "%s"}]}}\n' "$(native "$inst")" \
    > "$2/plugins/installed_plugins.json"
}
hooks5() { # hooks5 <brain> <config dir> -> the report's check-5 line
  ( cd "$1" && PATH="$T/bin-both:$PATH" HOME="$T/home" CLAUDE_CONFIG_DIR="$(native "$2")" env -u BRAIN_DIR bash "$V" "$1" >/dev/null 2>&1 )
  grep -a ' 5 Brain+hooks' "$1/docs/maintenance/$NAME"
}
plugin_brain "$T/brain9" "$T/cfg9" yes
line=$(hooks5 "$T/brain9" "$T/cfg9")
case "$line" in "OK    5 Brain+hooks"*"plugin brain-core@fx"*"appears"*) ok "plugin-shipped bootup hook: OK, and the bootup ran";; *) bad "plugin-shipped bootup hook: '$line'";; esac
plugin_brain "$T/brain9b" "$T/cfg9b" no
line=$(hooks5 "$T/brain9b" "$T/cfg9b")
case "$line" in "FAIL  5 Brain+hooks"*"runs no core/helpers/session-bootup.sh"*) ok "plugin cache without hooks/, no settings line: FAIL";; *) bad "no hook anywhere: '$line'";; esac

echo
if (( fails )); then echo "onboarding-verify-test: $fails FAILURE(S)"; exit 1; fi
echo "onboarding-verify-test: all checks passed"
