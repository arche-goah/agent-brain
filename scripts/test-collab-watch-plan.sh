#!/usr/bin/env bash
# covers: collab-watch-plan.py collab-watch.sh
# Fixture for the collab-watch plan step: scope resolution in BOTH directions and the config
# rules that keep two watches from silently eating each other's events.
#
# WHY both directions: a filter is the one place a watch can look armed and be blind. Every
# scope gets a positive check (its party IS reported) and a negative one (the other party is
# NOT) — a resolver that returned "everyone" for every scope would pass the positive half.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
PLAN="$HERE/collab-watch-plan.py"
fails=0; checks=0
ok()  { checks=$((checks + 1)); }
bad() { checks=$((checks + 1)); fails=$((fails + 1)); echo "  FAIL $*"; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# The temp dir only reaches python as an ARGUMENT (Git Bash converts argv), never as data.
write_cfg() { printf '%s\n' "$2" > "$T/$1"; }
write_cfg good.json '{
  "shared_memory": {"repo": "~/Projects/shared memory", "interval": 120},
  "repo_watches": [
    {"tag": "core", "repos": ["acme/core"], "interval": 300},
    {"tag": "suites", "repos": ["acme/suite-a", "acme/suite-b"], "interval": 600}
  ],
  "parallel_sessions": {"interval": 60},
  "parties": [
    {"id": "op-mac", "github": "op-login", "label": "this machine", "kind": "self"},
    {"id": "op-win", "github": "op-login", "label": "the other own machine", "kind": "self"},
    {"id": "ann-main", "github": "AnnLogin", "label": "Ann", "kind": "peer"},
    {"id": "ann-laptop", "github": "AnnLogin", "label": "Ann", "kind": "peer"},
    {"id": "bob-win", "github": "bob-lights", "label": "Bob", "kind": "peer"}
  ]
}'

field() { "$PY" "$PLAN" "$T/${3:-good.json}" "$1" 2>/dev/null | tr -d '\r' \
            | awk -v k="$2" '$1 == k { $1 = ""; sub(/^ /, ""); print }'; }
has()   { local g; g=$(field "$1" "$2" "${4:-}"); [[ "$g" == *"$3"* ]] && ok || bad "scope=$1 $2 should contain '$3', got '$g'"; }
hasnt() { local g; g=$(field "$1" "$2" "${4:-}"); [[ "$g" != *"$3"* ]] && ok || bad "scope=$1 $2 must NOT contain '$3', got '$g'"; }
rc_is() { "$PY" "$PLAN" "$T/${3:-good.json}" "$2" >/dev/null 2>&1; local rc=$?; [[ $rc -eq $1 ]] && ok || bad "scope='$2' cfg=${3:-good.json}: rc $rc, expected $1"; }

echo "scope all = no filter"
has all SCOPE_LOGINS "-"; has all SCOPE_PARTIES "-"; rc_is 0 all

echo "scope peers = every peer, no own machine"
has peers SCOPE_LOGINS AnnLogin; has peers SCOPE_LOGINS bob-lights
has peers SCOPE_PARTIES ann-main; has peers SCOPE_PARTIES bob-win
hasnt peers SCOPE_LOGINS op-login; hasnt peers SCOPE_PARTIES op-mac

echo "one peer: present, the OTHER peer demonstrably absent"
has ann SCOPE_LOGINS AnnLogin; hasnt ann SCOPE_LOGINS bob-lights
has ann SCOPE_PARTIES ann-main; has ann SCOPE_PARTIES ann-laptop   # one person, two machines
hasnt ann SCOPE_PARTIES bob-win
has bob SCOPE_LOGINS bob-lights; hasnt bob SCOPE_LOGINS AnnLogin; hasnt bob SCOPE_PARTIES ann-laptop
has bob-win SCOPE_PARTIES bob-win          # addressed by party id
has annlogin SCOPE_PARTIES ann-main        # addressed by login, case-insensitive

echo "refusals: own machine, unknown, empty"
rc_is 64 op-win        # own machines share one account; a login filter cannot separate them
rc_is 64 "this machine"
rc_is 64 colleague     # a ROLE word names nobody once there are two peers
rc_is 64 ""

echo "plan lines"
out=$("$PY" "$PLAN" "$T/good.json" all | tr -d '\r')
grep -qx 'SM 120 ~/Projects/shared memory' <<<"$out" && ok || bad "SM line keeps ~ and the space verbatim: $out"
grep -qx 'REPO core 300 acme/core' <<<"$out" && ok || bad "REPO core line: $out"
grep -qx 'REPO suites 600 acme/suite-a acme/suite-b' <<<"$out" && ok || bad "REPO suites line: $out"
grep -qx 'SESSIONS 60' <<<"$out" && ok || bad "SESSIONS line: $out"

echo "config rules (each one a way two watches silently eat events)"
write_cfg duptag.json '{"repo_watches": [
  {"tag": "x", "repos": ["acme/a"], "interval": 300},
  {"tag": "x", "repos": ["acme/b"], "interval": 60}]}'
rc_is 1 all duptag.json        # one tag = one cursor shared by two cadences
write_cfg duprepo.json '{"repo_watches": [
  {"tag": "x", "repos": ["acme/a"], "interval": 300},
  {"tag": "y", "repos": ["acme/a"], "interval": 60}]}'
rc_is 1 all duprepo.json
rc_is 1 all ../templates-missing.json   # no config at all
cp "$HERE/../templates/rules-instance/collab-watch.json" "$T/template.json"
rc_is 1 all template.json      # unfilled template refused, not armed blind
msg=$("$PY" "$PLAN" "$T/template.json" all 2>&1)
[[ "$msg" == *placeholder* ]] && ok || bad "template refusal names the placeholder: $msg"
write_cfg short.json '{"repo_watches": [{"tag": "x", "repos": ["acme/a"], "interval": 5}]}'
rc_is 1 all short.json
write_cfg badparty.json '{"parallel_sessions": {"interval": 60}, "parties": [{"id": "a", "github": "a", "label": "A", "kind": "friend"}]}'
rc_is 1 all badparty.json

echo "arm script --dry-run prints the plan and arms nothing"
dry=$(COLLAB_WATCH_CONFIG="$T/good.json" bash "$HERE/collab-watch.sh" --dry-run 2>&1 | tr -d '\r')
grep -q '^REPO core 300 acme/core$' <<<"$dry" && ok || bad "--dry-run output: $dry"
COLLAB_WATCH_CONFIG="$T/good.json" COLLAB_WATCH_SCOPE=op-win bash "$HERE/collab-watch.sh" --dry-run >/dev/null 2>&1
[[ $? -eq 64 ]] && ok || bad "arm script passes the scope refusal through (rc 64)"

echo
if [[ $fails -eq 0 ]]; then echo "test-collab-watch-plan: all $checks checks passed"; exit 0; fi
echo "test-collab-watch-plan: $fails of $checks checks FAILED"; exit 1
