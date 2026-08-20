#!/usr/bin/env bash
# covers: ecosystem-sync.py (consumer_plugin generation) + session-bootup.sh (consumer_plugin
# consumption in the suite-update check)
#
# Effect proof for agent-brain PR #75's review finding: a first version of the
# dev-checkout-vs-plugin guard keyed on a `plugin_name` field nothing ever generated —
# it worked only in the one file it was hand-typed into. This fixture builds an
# ecosystem.json shaped like a REAL consuming brain (no hand annotations) and proves
# both halves of the mechanism that replaced it:
#   1. ecosystem-sync.py --write computes `consumer_plugin` on a suite repo entry by
#      matching its git remote against a locally cached marketplace.json, not by name.
#   2. session-bootup.sh's suite-update check skips a suite that HAS `consumer_plugin`
#      (the dev checkout may legitimately lag — the plugin is what the operator uses)
#      and still fires for one that does NOT (the checkout IS the consumer there).
# Both directions are asserted per this repo's detector discipline — a guard proven
# only to skip, never to fire, is not proven at all.
#
# All bash-to-python path handoffs go through ENV VARS, read with os.environ — never
# string-interpolated into generated Python/JSON source. A Windows native path
# ("C:\Users\...") contains backslashes that are invalid escapes in both a Python
# string literal and JSON text; an env var value carries them unparsed either way.
#
# Usage: bash scripts/test-suite-plugin-linkage.sh   (exit 0 = all fixtures pass)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
# Windows: this repo's own python3 is the native (non-MSYS) interpreter — it does not
# resolve the /tmp/... form mktemp hands back under Git Bash (same class as the R vs
# R_native split in session-bootup.sh). Converting once, up front, keeps every path
# below usable by both git (fine with either form) and python (needs the native one).
command -v cygpath >/dev/null 2>&1 && T="$(cygpath -w "$T")"
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
git_() { git -c user.email=t@t -c user.name=t "$@"; }

PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python

write_ecosystem() { # write_ecosystem <brain-dir> <suite-repo-path> [consumer_plugin-or-empty]
  BRAIN_TARGET="$1" SUITE_PATH="$2" SUITE_REMOTE="${3:-}" CONSUMER="${4:-}" "$PY" -c "
import json, os
entry = {'path': os.environ['SUITE_PATH'], 'kind': 'suite', 'commit': 'x',
         'version': 'v1.1.21', 'requires_core': None,
         'remote': os.environ.get('SUITE_REMOTE') or None}
if os.environ.get('CONSUMER'):
    entry['consumer_plugin'] = os.environ['CONSUMER']
d = {'repos': {'fake-suite-repo': entry}, 'plugins': {}, 'core_contract': '1.1.0'}
json.dump(d, open(os.path.join(os.environ['BRAIN_TARGET'], 'config', 'ecosystem.json'), 'w'))
"
}
read_consumer_plugin() { # read_consumer_plugin <brain-dir>
  BRAIN_TARGET="$1" "$PY" -c "
import json, os
d = json.load(open(os.path.join(os.environ['BRAIN_TARGET'], 'config', 'ecosystem.json')))
print(d['repos']['fake-suite-repo'].get('consumer_plugin'))
"
}

# ============================================================================
# Part 1 — ecosystem-sync.py generates consumer_plugin from local, no-network data
# ============================================================================
CFG="$T/cfg"
mkdir -p "$CFG/plugins/marketplaces/fake-market/.claude-plugin"
cat > "$CFG/plugins/installed_plugins.json" <<'JSON'
{"plugins": {"fakesuite@fake-account": [{"version": "1.1.21", "gitCommitSha": "abc123def456"}]}}
JSON
cat > "$CFG/plugins/marketplaces/fake-market/.claude-plugin/marketplace.json" <<'JSON'
{"plugins": [{"name": "fakesuite", "source": {"source": "github", "repo": "fake-account/fake-suite-repo"}}]}
JSON

SRC="$T/suite-src"
mkdir -p "$SRC"
git_ -C "$SRC" init --quiet -b main
echo x > "$SRC/f"
git_ -C "$SRC" add -A
git_ -C "$SRC" commit --quiet -m init
git_ -C "$SRC" tag v1.1.20
git_ -C "$SRC" remote add origin "https://github.com/fake-account/fake-suite-repo.git"

BRAIN="$T/brain"
mkdir -p "$BRAIN/config"
write_ecosystem "$BRAIN" "$SRC"
cp "$ROOT/core-contract.json" "$BRAIN/config/core-contract.json" 2>/dev/null || echo '{"contract_version":"1.1.0"}' > "$BRAIN/config/core-contract.json"

out=$(cd "$BRAIN" && CLAUDE_CONFIG_DIR="$CFG" BRAIN_DIR="$BRAIN" "$PY" "$ROOT/scripts/ecosystem-sync.py" --write 2>&1)
rc=$?
[ "$rc" -eq 0 ] && ok "ecosystem-sync --write runs clean on a fresh brain" \
  || bad "ecosystem-sync --write failed (rc=$rc): ${out:0:300}"

got=$(read_consumer_plugin "$BRAIN")
[ "$got" = "fakesuite@fake-account" ] && ok "consumer_plugin stamped from local marketplace cache, no hand-typed field" \
  || bad "consumer_plugin not linked (got: $got) — presence-without-effect, the class this PR is fixing"

# negative: no matching installed plugin -> field stays absent, not guessed
CFG2="$T/cfg-empty"
mkdir -p "$CFG2/plugins"
echo '{"plugins": {}}' > "$CFG2/plugins/installed_plugins.json"
write_ecosystem "$BRAIN" "$SRC"
CLAUDE_CONFIG_DIR="$CFG2" BRAIN_DIR="$BRAIN" "$PY" "$ROOT/scripts/ecosystem-sync.py" --write >/dev/null 2>&1
got2=$(read_consumer_plugin "$BRAIN")
[ "$got2" = "None" ] && ok "no installed plugin -> consumer_plugin stays unset (no false link)" \
  || bad "consumer_plugin set without a matching installed plugin (got: $got2)"

# ============================================================================
# Part 2 — session-bootup.sh reads consumer_plugin to decide the suite-update line
# ============================================================================
BOOTUP="$ROOT/helpers/session-bootup.sh"
[ -f "$BOOTUP" ] || BOOTUP="$ROOT/../helpers/session-bootup.sh"

mkremote() { # mkremote <tagged-version> -> prints path to a bare repo tagged v<version>
  local ver="$1" d="$T/remote-$RANDOM.git" src="$T/remote-src-$RANDOM"
  mkdir -p "$src"
  git_ -C "$src" init --quiet -b main
  (cd "$src" && echo x > f && git_ add -A && git_ commit --quiet -m init && git_ tag "v$ver")
  git_ init --quiet --bare "$d"
  git_ -C "$src" remote add origin "$d"
  git_ -C "$src" push --quiet origin main --tags
  printf '%s' "$d"
}
mkcheckout() { # mkcheckout <remote-bare-path> -> local clone, sitting exactly on its tag
  local remote="$1" d="$T/checkout-$RANDOM"
  git_ clone --quiet "$remote" "$d"
  printf '%s' "$d"
}

REMOTE=$(mkremote 1.1.21)
CHECKOUT=$(mkcheckout "$REMOTE")
# advance the remote past what the checkout has, so a real drift exists to detect
(cd "$T" && git_ clone --quiet "$REMOTE" pusher && cd pusher \
  && echo y >> f && git_ add -A && git_ commit --quiet -m bump && git_ tag v1.1.22 \
  && git_ push --quiet origin main --tags) >/dev/null 2>&1

TB="$T/testbrain"
mkdir -p "$TB/config"

run_bootup_suite_line() { # run_bootup_suite_line <consumer-plugin-or-empty> -> the suite line (if any)
  write_ecosystem "$TB" "$CHECKOUT" "$REMOTE" "$1"
  (cd "$TB" && CLAUDE_PROJECT_DIR="$TB" bash "$BOOTUP" 2>/dev/null) | grep -o 'suite update available[^—]*' || true
}

with_plugin=$(run_bootup_suite_line "fakesuite@fake-account")
[ -z "$with_plugin" ] && ok "consumer_plugin set -> dev-checkout lag stays silent" \
  || bad "false positive survived with consumer_plugin set: $with_plugin"

without_plugin=$(run_bootup_suite_line "")
[ -n "$without_plugin" ] && ok "no consumer_plugin -> genuine checkout drift still reported" \
  || bad "guard over-suppressed: no consumer_plugin, real drift, but nothing was reported"

echo
[ "$fail" -eq 0 ] && echo "suite-plugin-linkage fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
