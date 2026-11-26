#!/usr/bin/env bash
# covers: shell-tools
# test-shell-tools.sh — no core helper reads a shell command only when the tool was `Bash`.
#
# WHY (measured 2026-11-24 on the macOS instance at the train head 72c6663): ten core gates compared the tool name
# with 'Bash' alone; on Windows the main shell is the PowerShell tool, so a background run, a search, a diff read
# or an own failure there went unseen. One list now lives in helpers/shell-tools.cjs. A site that must read only
# Bash says so on its line: `// bash-only: <why>`.
# Usage: bash scripts/test-shell-tools.sh   (exit 0 = pass)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# Prints every helper line that compares a tool name with 'Bash' and names neither PowerShell nor a reason.
scan() {
  node -e '
    const fs = require("fs"), path = require("path");
    const dir = process.argv[1];
    const rx = /\b(?:name|tool_name)\s*[!=]==?\s*["\x27]Bash["\x27]/;
    for (const f of fs.readdirSync(dir).filter((x) => x.endsWith(".cjs") && x !== "shell-tools.cjs")) {
      fs.readFileSync(path.join(dir, f), "utf8").split("\n").forEach((l, i) => {
        if (rx.test(l) && !/PowerShell|\bps\b|bash-only:\s*\S/.test(l)) console.log(`${f}:${i + 1}: ${l.trim()}`);
      });
    }' "$(native "$1")"
}

out=$(scan "$ROOT/helpers")
[ -z "$out" ] && ok "no core helper reads a shell command from Bash alone" || bad "Bash-only sites:
$out"
node -e 'const s=require(process.argv[1]); process.exit(s.isShell("Bash") && s.isShell("PowerShell") && !s.isShell("Agent") ? 0 : 1)' \
  "$(native "$ROOT/helpers/shell-tools.cjs")" && ok "isShell: Bash and PowerShell yes, Agent no" || bad "isShell answers wrong"

# Negative controls: the scanner finds the incident's form and lets the two declared forms pass.
mkdir -p "$T/h"
printf "if (b.name === 'Bash') x();\n" > "$T/h/a.cjs"
printf "if (input.tool_name !== 'Bash') return '';\n" > "$T/h/b.cjs"
printf "if (b.name === 'Bash' || b.name === 'PowerShell') x();\n" > "$T/h/c.cjs"
printf "if (b.name === 'Bash') x();   // bash-only: reads a bash heredoc\n" > "$T/h/d.cjs"
out=$(scan "$T/h")
case "$out" in *"a.cjs:1"*) ok "the incident form (=== 'Bash') is found";; *) bad "=== 'Bash' not found: $out";; esac
case "$out" in *"b.cjs:1"*) ok "the !== 'Bash' form is found";; *) bad "!== 'Bash' not found: $out";; esac
case "$out" in *"c.cjs"*|*"d.cjs"*) bad "a PowerShell or bash-only line was flagged: $out";; *) ok "PowerShell named or a bash-only reason passes";; esac

# Behaviour per gate lives in the gate fixtures: a PowerShell case each in test-review-claim-gate.sh,
# test-stoppen-gate.sh and test-foreign-entry-gate.sh.

[ "$fail" -eq 0 ] && echo "shell-tools: all cases pass" || { echo "shell-tools: FAILURES"; exit 1; }
