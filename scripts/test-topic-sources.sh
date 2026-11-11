#!/usr/bin/env bash
# covers: topic-sources
# Fixture test for helpers/topic-sources.cjs — both directions.
# The incident (2026-11-11): a shopping total was built from one project's files; the overview in the
# same folder was never opened. Must: a prompt that hits a topic lists EVERY source file of it (files
# and folders, recursive, text only, no dot files) and names the decision register; a prompt that hits
# no topic, missing data, bad JSON, a peer message, a notification or a Stop-hook echo stays silent; two topics hit both.
# Usage: bash scripts/test-topic-sources.sh (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
H="$(cd "$(dirname "$0")" && pwd)/../helpers/topic-sources.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
[ -f "$H" ] || { echo "  FAIL helper missing: $H"; exit 1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }

P="$T/brain"; mkdir -p "$P/.claude/rules" "$P/docs/shop/projA" "$P/docs/net"
echo x > "$P/docs/list.md"; echo x > "$P/docs/shop/overview.md"; echo x > "$P/docs/shop/projA/order.md"
echo x > "$P/docs/shop/projA/photo.png"; echo x > "$P/docs/shop/.hidden.md"; echo x > "$P/docs/net/plan.md"
printf '%s' '{"topics":[{"name":"shopping","prompt_patterns":["shopping","\\bnet\\b"],"sources":["docs/list.md","docs/shop"],"also":"the project ledgers"},{"name":"network","prompt_patterns":["router"],"sources":["docs/net"]}]}' > "$P/.claude/rules/topic-sources.json"
export CLAUDE_PROJECT_DIR="$(native "$P")"
say() { printf '{"prompt":%s}' "$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1")" | node "$H"; }

out="$(say 'what is the total, net?')"
case "$out" in *'docs/list.md'*'docs/shop/overview.md'*'docs/shop/projA/order.md'*) ok "topic hit lists every source, folders recursive";; *) bad "sources missing: $out";; esac
case "$out" in *photo.png*|*.hidden*) bad "non-text or dot file listed";; *) ok "only text files, no dot files";; esac
case "$out" in *decision-register*) ok "names the decision register";; *) bad "register not named";; esac
case "$out" in *'docs/net/plan.md'*) bad "unhit topic listed";; *) ok "unhit topic not listed";; esac
out="$(say 'shopping and the router today')"
case "$out" in *'topic="shopping"'*'topic="network"'*) ok "two topics hit both";; *) bad "two topics: $out";; esac
out="$(say 'what time is it')"
[ -z "$out" ] && ok "no topic, silent" || bad "no-topic prompt touched: $out"
out="$(say '<cross-session-message from="peer">the shopping session asks about the net total</cross-session-message>')"
[ -z "$out" ] && ok "peer message, silent" || bad "peer message touched: $out"
out="$(say '<task-notification><summary>shopping list updated</summary></task-notification>')"
[ -z "$out" ] && ok "task notification, silent" || bad "notification touched: $out"
out="$(say 'Stop hook feedback: shopping decision not carried')"
[ -z "$out" ] && ok "stop-hook echo, silent" || bad "stop echo touched: $out"
out="$(printf '{"prompt":"shopping net total?","origin":{"kind":"peer"}}' | node "$H")"
[ -z "$out" ] && ok "peer origin, silent" || bad "peer origin touched: $out"
echo 'not json' > "$P/.claude/rules/topic-sources.json"
out="$(say 'shopping')"
[ -z "$out" ] && ok "bad data, silent" || bad "bad data touched: $out"
rm "$P/.claude/rules/topic-sources.json"
out="$(say 'shopping')"
[ -z "$out" ] && ok "no data, silent" || bad "no data touched: $out"

[ "$fail" = 0 ] && echo "test-topic-sources: all passed" || echo "test-topic-sources: FAILURES"
exit "$fail"
