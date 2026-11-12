#!/usr/bin/env bash
# covers: content-review-gate pr-risk
# test-content-review-gate.sh — a PR is built and reviewed at the model its risk needs, and approved and merged
# only on a content review (Fit / Design / Cost / Model). Both directions, no network: a fake gh answers.
#
# WHY (operator orders 2026-11-10): three PRs were approved on green fixtures and an OS run; one carried a second
# copy of a rule. And: nothing critical is built or reviewed with a smaller model.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/helpers/content-review-gate.cjs"
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
N="$(native "$T")"  # native form: the gate (node) reads the --body-file paths below
printf 'process.stdout.write(require("fs").readFileSync(process.env.PR_JSON, "utf8"))\n' > "$T/gh.js"
# a core-like repo: its root carries pr-risk.json
git init -q "$T/core"
cp "$ROOT/pr-risk.json" "$T/core/pr-risk.json"
transcript() { printf '{"type":"assistant","message":{"model":"%s"}}\n' "$1" > "$T/t.jsonl"; }
pr() { node -e 'const fs=require("fs"); const rd=(l)=>(l||"").split(",").filter(Boolean).map((f)=>({body: fs.readFileSync(f,"utf8")})); process.stdout.write(JSON.stringify({body: process.argv[1], files: process.argv[2].split(",").filter(Boolean).map((p) => ({path: p})), comments: rd(process.argv[3]), reviews: rd(process.argv[4])}))' "$@" > "$T/pr.json"; }
probe() { # $1 label, $2 command, $3 block|allow, [$4 staged/branch files, newline list]
  local out rc
  out=$(printf '%s' "{\"tool_name\":\"Bash\",${AGENT:+\"agent_id\":\"$AGENT\",}\"cwd\":\"$(native "$T/core")\",\"transcript_path\":\"$(native "$T/t.jsonl")\",\"tool_input\":{\"command\":$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$2")}}" \
        | PR_JSON="$(native "$T/pr.json")" CONTENT_REVIEW_GATE_GH="$(native "$T/gh.js")" CONTENT_REVIEW_GATE_FILES="${4-}" \
          node "$(native "$GATE")" 2>&1); rc=$?
  if [ "$rc" -eq 2 ]; then [ "$3" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:200}"
  else [ "$3" = allow ] && ok "$1 allows" || bad "$1 did NOT block (rc=$rc)"; fi
}
A="aaaaaaaaaa"; B="bbbbbbbbbb"
GOOD="Fit: no existing gate asks for a design verdict, searched helpers/README.md
Design: one reader for approval and merge, data in pr-risk.json, no second copy
Cost: runs only on gh pr and git commit calls, one gh view per merge"

# CHECK 0 - commit at build time
transcript claude-sonnet-5-5
probe "sonnet commits a hook change in the core" "git commit -m x" block "hooks/hooks.json"
probe "sonnet commits a script change (medium)" "git commit -m x" allow "scripts/foo.py"
probe "sonnet commits docs (low)" "git -C . commit -m x" allow "docs/a.md"
transcript claude-opus-5-5
probe "opus commits a gate change" "git commit -m x" allow "helpers/x-gate.cjs"
transcript claude-opus-6
probe "a newer opus version counts as opus" "git commit -m x" allow "helpers/x-gate.cjs"
transcript claude-sonnet-5-5
probe "not a commit (git status)" "git status" allow "hooks/hooks.json"

# CHECK 1 - gh pr create
printf 'Fix it.\n' > "$T/body-none.md"
printf 'Risk: low - one doc line\n' > "$T/body-low.md"
printf 'Risk: high - a gate wired in every brain blocks calls\n' > "$T/body-high.md"
transcript claude-opus-5-5
probe "create without Risk line" "gh pr create -R o/r --body-file $N/body-none.md" block "docs/a.md"
probe "create below the file floor" "gh pr create -R o/r --body-file $N/body-low.md" block "helpers/x-gate.cjs"
probe "create with high risk on opus" "gh pr create -R o/r --body-file $N/body-high.md" allow "helpers/x-gate.cjs"
transcript claude-sonnet-5-5
probe "create with high risk on sonnet" "gh pr create -R o/r --body-file $N/body-high.md" block "helpers/x-gate.cjs"
probe "create low risk on sonnet" "gh pr create -R o/r --body-file $N/body-low.md" allow "docs/a.md"
# 2026-11-12: `gh pr create -R <core>` run from ANOTHER repo's checkout (the brain) was scored by that checkout's branch
# (a brain script set the floor). Here the cwd is a brain-like repo whose branch carries a gate file; -R names o/r.
git init -q "$T/brain"
git -C "$T/brain" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
git -C "$T/brain" update-ref refs/remotes/origin/main HEAD
git -C "$T/brain" remote add origin https://github.com/x/brain.git
mkdir -p "$T/brain/helpers"; printf 'x\n' > "$T/brain/helpers/x-gate.cjs"
git -C "$T/brain" add helpers/x-gate.cjs
git -C "$T/brain" -c user.name=t -c user.email=t@t commit -q -m gate
foreign=$(printf '%s' "{\"tool_name\":\"Bash\",\"cwd\":\"$(native "$T/brain")\",\"transcript_path\":\"$(native "$T/t.jsonl")\",\"tool_input\":{\"command\":\"gh pr create -R o/r --body-file $N/body-low.md\"}}" \
  | env -u CONTENT_REVIEW_GATE_FILES CONTENT_REVIEW_GATE_GH="$(native "$T/gh.js")" PR_JSON="$(native "$T/pr.json")" node "$(native "$GATE")" 2>&1); frc=$?
[ "$frc" -ne 2 ] && ok "create -R from another repo's checkout: its branch files do not set the floor" \
  || bad "create -R from another repo's checkout was scored by the checkout: ${foreign:0:200}"
[[ "$foreign" == *"not this checkout"* ]] && ok "  ... and says the floor was not checked" || bad "  ... no 'not this checkout' note"
# review of #478 (Windows instance): a trailing synthetic entry or an unknown family is no model at all
printf '{"type":"assistant","message":{"model":"claude-sonnet-5-5"}}\n{"type":"assistant","message":{"model":"<synthetic>"}}\n' > "$T/t.jsonl"
probe "a trailing <synthetic> entry: the last real model counts (sonnet, high)" "gh pr create -R o/r --body-file $N/body-high.md" block "helpers/x-gate.cjs"
probe "a trailing <synthetic> entry does not block a low PR" "gh pr create -R o/r --body-file $N/body-low.md" allow "docs/a.md"
# counter-check of #478 (macOS instance): a "model" key outside an assistant record is no session model -
# an Agent call with a model override, a tool result that prints JSON with a model field
printf '{"type":"assistant","message":{"model":"claude-opus-5-5"}}\n{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Agent","input":{"model":"haiku"}}],"model":"claude-opus-5-5"},"x":1}\n{"type":"user","message":{"content":[{"type":"tool_result","content":"{\\"model\\":\\"haiku\\"}"}]}}\n{"type":"user","toolUseResult":{"model":"sonnet"}}\n' > "$T/t.jsonl"
probe "a sub-agent override or a printed model field is not the session model (opus, high)" "gh pr create -R o/r --body-file $N/body-high.md" allow "helpers/x-gate.cjs"
transcript "<synthetic>"
probe "only <synthetic>: model not measured, not checked" "gh pr create -R o/r --body-file $N/body-high.md" allow "helpers/x-gate.cjs"
transcript claude-zeta-1
probe "an unknown family is not measured, not the smallest" "git commit -m x" allow "hooks/hooks.json"

# Windows review of #478: a sub-agent's call (agent_id) is judged by the sub-agent's own transcript, both directions
mkdir -p "$T/t/subagents"
transcript claude-opus-5-5
printf '{"type":"assistant","message":{"model":"claude-haiku-5-5"}}\n' > "$T/t/subagents/agent-a1.jsonl"
AGENT=a1 probe "a haiku sub-agent under an opus parent commits high risk" "git commit -m x" block "hooks/hooks.json"
transcript claude-sonnet-5-5
printf '{"type":"assistant","message":{"model":"claude-opus-5-5"}}\n' > "$T/t/subagents/agent-a2.jsonl"
AGENT=a2 probe "an opus sub-agent under a sonnet parent commits high risk" "git commit -m x" allow "hooks/hooks.json"
AGENT=a9 probe "a sub-agent without its transcript is not measured, never the parent's model" "git commit -m x" allow "hooks/hooks.json"
probe "the sonnet parent itself still commits no high risk" "git commit -m x" block "hooks/hooks.json"

# CHECK 2/3 - approval and Model line
printf '%s\nModel: claude-opus-5-5\n' "$GOOD" > "$T/rev-opus.md"
printf 'Tests green on macOS.\n' > "$T/rev-thin.md"
printf 'Fit: ok\nDesign: ok\nCost: ok\nModel: claude-opus-5-5\n' > "$T/rev-empty.md"
pr "Risk: high - gate <!-- instance-key: $A -->" "helpers/x-gate.cjs" ""
transcript claude-opus-5-5
probe "approve with the full block on opus" "gh pr review 5 -R o/r --approve --body-file $N/rev-opus.md" allow
probe "approve on tests only" "gh pr review 5 -R o/r --approve --body-file $N/rev-thin.md" block
probe "approve with empty answers" "gh pr review 5 -R o/r --approve --body-file $N/rev-empty.md" block
probe "a plain comment needs no block" "gh pr comment 5 -R o/r --body-file $N/rev-thin.md" allow
transcript claude-sonnet-5-5
probe "Model line claims opus, session is sonnet" "gh pr comment 5 -R o/r --body-file $N/rev-opus.md" block
printf '%s\nModel: claude-sonnet-5-5\n' "$GOOD" > "$T/rev-sonnet.md"
probe "sonnet approves a high-risk PR" "gh pr review 5 -R o/r --approve --body-file $N/rev-sonnet.md" block
pr "Risk: low - docs <!-- instance-key: $A -->" "docs/a.md" ""
probe "sonnet approves a low-risk PR" "gh pr review 5 -R o/r --approve --body-file $N/rev-sonnet.md" allow
# Windows review of #478: "Model: reviewed by Opus" names opus, not the word "reviewed"
printf '%s\nModel: reviewed by Opus 5.5\n' "$GOOD" > "$T/rev-prose.md"
pr "Risk: high - gate <!-- instance-key: $A -->" "helpers/x-gate.cjs" ""
transcript claude-opus-5-5
probe "approve with a prose Model line naming opus" "gh pr review 5 -R o/r --approve --body-file $N/rev-prose.md" allow
transcript claude-sonnet-5-5
probe "a prose Model line claiming opus on a sonnet session" "gh pr comment 5 -R o/r --body-file $N/rev-prose.md" block

# CHECK 4 - merge
M="gh pr merge 5 -R o/r --merge"
printf '%s\nModel: claude-opus-5-5 <!-- instance-key: %s -->\n' "$GOOD" "$B" > "$T/c-other.md"
printf '%s\nModel: claude-opus-5-5 <!-- instance-key: %s -->\n' "$GOOD" "$A" > "$T/c-self.md"
printf '%s\nModel: claude-sonnet-5-5 <!-- instance-key: %s -->\n' "$GOOD" "$B" > "$T/c-small.md"
printf 'macOS OK at abc1234 <!-- instance-key: %s -->\n' "$B" > "$T/c-os.md"
pr "Risk: high - gate <!-- instance-key: $A -->" "helpers/x-gate.cjs" "" "$T/c-other.md"
probe "merge with another instance's opus content review (as a review)" "$M" allow
pr "Risk: high - gate <!-- instance-key: $A -->" "helpers/x-gate.cjs" "$T/c-self.md"
probe "merge with only the author's own review" "$M" block
pr "Risk: high - gate <!-- instance-key: $A -->" "helpers/x-gate.cjs" "$T/c-small.md"
probe "merge reviewed on a too small model" "$M" block
pr "Risk: high - gate <!-- instance-key: $A -->" "helpers/x-gate.cjs" "$T/c-os.md"
probe "merge with an OS check only" "$M" block
probe "override names why" "$M # CONTENT-REVIEW-OK: data PR, no second reviewer in this repo" allow
pr "## Merge train t1
- #7 fix/a abc
- #8 fix/b def" "" ""
probe "train PR whose members lack a content review" "$M" block

[ "$fail" -eq 0 ] && echo "content-review-gate fixtures: ALL passed" || { echo "content-review-gate fixtures: FAILURES"; exit 1; }
