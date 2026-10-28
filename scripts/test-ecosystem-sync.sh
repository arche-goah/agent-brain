#!/usr/bin/env bash
# covers: ecosystem-sync
# test-ecosystem-sync.sh — the lockfile writer keeps what it cannot re-derive and survives a suite
# that is consumed only as a plugin. No network: a fake config dir carries the plugin registry and
# the marketplace cache.
#
# WHY (2026-10-28, macOS instance): a suite entry with `path: null` (plugin only, no clone) crashed
# the run with a TypeError; and `--write` dropped content-toolsuite's `consumer_plugin` because the
# marketplace still names the repo by its old name — local-machinery then read the plugin as
# undeclared.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="$ROOT/scripts/ecosystem-sync.py"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# A suite clone whose origin carries the NEW name.
mkdir -p "$T/suite-b"
git -C "$T/suite-b" init -q
git -C "$T/suite-b" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$T/suite-b" remote add origin https://github.com/o/new-name.git

# The brain: lockfile with a plugin-only suite and the renamed suite.
mkdir -p "$T/brain/config"
CONTRACT_VERSION="$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["contract_version"])' "$(native "$ROOT/core-contract.json")")"
cat > "$T/brain/config/ecosystem.json" <<JSON
{"core_contract": "$CONTRACT_VERSION",
 "repos": {
  "suite-a": {"path": null, "kind": "suite", "remote": "https://github.com/o/suite-a.git", "consumer_plugin": "a-next@m"},
  "suite-b": {"path": "$(native "$T/suite-b")", "kind": "suite", "remote": "https://github.com/o/new-name.git", "consumer_plugin": "b-next@m"}
 },
 "plugins": {}}
JSON

# The user config: both plugins installed; the marketplace lists b-next under the OLD repo name.
mkdir -p "$T/cfg/plugins/marketplaces/m/.claude-plugin"
printf '%s' '{"version":2,"plugins":{"a-next@m":[{"version":"0.2.0","gitCommitSha":"aaaaaaaaaaaa"}],"b-next@m":[{"version":"0.4.0","gitCommitSha":"bbbbbbbbbbbb"}]}}' \
  > "$T/cfg/plugins/installed_plugins.json"
printf '%s' '{"plugins":[{"name":"a-next","source":{"source":"github","repo":"o/suite-a"}},{"name":"b-next","source":{"source":"github","repo":"o/old-name"}}]}' \
  > "$T/cfg/plugins/marketplaces/m/.claude-plugin/marketplace.json"

run() { BRAIN_DIR="$(native "$T/brain")" CLAUDE_CONFIG_DIR="$(native "$T/cfg")" "$PY" "$(native "$SYNC")" "$@" 2>&1; }

out=$(run); rc=$?
printf '%s' "$out" | grep -aq 'Traceback' && bad "a plugin-only suite (path null) crashes the run: ${out:0:200}" \
  || ok "a plugin-only suite (path null) is skipped, no crash (rc=$rc)"
printf '%s' "$out" | grep -aq 'suite-b: consumer_plugin b-next@m kept, but the marketplace names o/old-name' \
  && ok "a renamed repo's consumer_plugin is kept and the mismatch is named" || bad "mismatch not named: $out"

# The lockfile path reaches python through the environment (docs/os-traps.md OS-6).
export EF; EF="$(native "$T/brain/config/ecosystem.json")"
run --write >/dev/null
"$PY" -c 'import json,os,sys; r=json.load(open(os.environ["EF"]))["repos"]; sys.exit(0 if r["suite-a"].get("consumer_plugin")=="a-next@m" and r["suite-b"].get("consumer_plugin")=="b-next@m" else 1)' \
  && ok "--write keeps consumer_plugin of both suites" || bad "--write dropped a consumer_plugin"

# Control: a consumer_plugin whose plugin is NOT installed still goes (nothing delivers the suite).
"$PY" -c 'import json,os; p=os.environ["EF"]; d=json.load(open(p)); d["repos"]["suite-b"]["consumer_plugin"]="gone@m"; json.dump(d, open(p,"w"))'
run --write >/dev/null
"$PY" -c 'import json,os,sys; sys.exit(0 if "consumer_plugin" not in json.load(open(os.environ["EF"]))["repos"]["suite-b"] else 1)' \
  && ok "a consumer_plugin no installed plugin carries is dropped (control)" || bad "a stale consumer_plugin survived"

echo
[ "$fail" -eq 0 ] && echo "test-ecosystem-sync: all checks passed" || echo "test-ecosystem-sync: FAILURES"
exit "$fail"
