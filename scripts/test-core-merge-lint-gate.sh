#!/usr/bin/env bash
# covers: core-merge-lint-gate
# Fixture for helpers/core-merge-lint-gate.cjs. No network: refs come from CORE_MERGE_LINT_REFS, stamps from a temp
# dir, the core repo from CORE_LINT_REPO (or from a temp checkout's origin). Both directions; rc 0 = all pass.
set -u
cd "$(dirname "$0")/.." || exit 1
G="helpers/core-merge-lint-gate.cjs"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
TN="$(native "$T")"
export CORE_LINT_REPO="example-org/core"
export CLAUDE_PROJECT_DIR="$TN"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
verdict() { # $1 name, $2 output, $3 block|allow
  case "$2" in *'"deny"'*) [ "$3" = block ] && ok "$1 blocks" || bad "$1 blocked";;
    *) [ "$3" = allow ] && ok "$1 allows" || bad "$1 did not block";; esac
}
hook() { node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",tool_input:{command:process.argv[1]}}))' "$1"; }
REFS='{"refs/pull/7/head":"aaaa111","refs/heads/main":"bbbb222"}'
probe() { verdict "$1" "$(hook "$2" | CORE_MERGE_LINT_REFS="$REFS" CORE_MERGE_LINT_STAMPS="$TN" node "$G")" "$3"; }
probe "core merge without a stamp" "gh pr merge 7 -R example-org/core --squash" block
: > "$T/aaaa111-bbbb222.ok"
probe "core merge with a stamp for head + main" "gh pr merge 7 -R example-org/core --squash" allow
probe "the --repo spelling with a stamp" "gh pr merge 7 --repo example-org/core --squash" allow
REFS='{"refs/pull/7/head":"aaaa111","refs/heads/main":"cccc333"}'
probe "same stamp, main moved" "gh pr merge 7 -R example-org/core --squash" block
probe "another repo is not gated" "gh pr merge 7 -R example-org/other --squash" allow
probe "the name as an argument is no merge" "grep -n 'gh pr merge 7 -R example-org/core' notes.md" allow
# The head is the branch, not the pull ref (2026-10-31: refs/pull/N/head one push behind the branch).
REFS='{"refs/pull/7/head":"aaaa111","branch-of-7":"eeee555","refs/heads/main":"cccc333"}'
: > "$T/aaaa111-cccc333.ok"
probe "a stamp for the stale pull ref while the branch moved on" "gh pr merge 7 -R example-org/core --squash" block
: > "$T/eeee555-cccc333.ok"
probe "a stamp for the branch head" "gh pr merge 7 -R example-org/core --squash" allow
# The repo is data: another configured core repo, the same command passes.
verdict "a brain whose core is another repo" "$(hook "gh pr merge 7 -R example-org/core-old --squash" | CORE_MERGE_LINT_REFS="$REFS" CORE_MERGE_LINT_STAMPS="$TN/none" node "$G")" allow
# No CORE_LINT_REPO: the origin of the core checkout decides (in a brain, its core/ submodule).
O="$T/checkout"; git init -q "$O"; git -C "$O" remote add origin "https://github.com/example-org/core.git"
verdict "repo from the checkout's origin, no stamp" "$(hook "gh pr merge 9 -R example-org/core" | env -u CORE_LINT_REPO CORE_LINT_CHECKOUT="$(native "$O")" CORE_MERGE_LINT_REFS='{"branch-of-9":"ffff666","refs/heads/main":"cccc333"}' CORE_MERGE_LINT_STAMPS="$TN" node "$G")" block
git -C "$O" remote set-url origin "https://github.com/example-org/elsewhere.git"
verdict "the checkout's origin is another repo" "$(hook "gh pr merge 9 -R example-org/core" | env -u CORE_LINT_REPO CORE_LINT_CHECKOUT="$(native "$O")" CORE_MERGE_LINT_REFS='{"branch-of-9":"ffff666","refs/heads/main":"cccc333"}' CORE_MERGE_LINT_STAMPS="$TN" node "$G")" allow
verdict "no readable core repo = inert" "$(hook "gh pr merge 9 -R example-org/core" | env -u CORE_LINT_REPO CORE_LINT_CHECKOUT="$TN/nowhere" CORE_MERGE_LINT_REFS='{"branch-of-9":"ffff666","refs/heads/main":"cccc333"}' CORE_MERGE_LINT_STAMPS="$TN" node "$G")" allow
# Push of a core branch (2026-10-30): stamp per pushed commit.
PS="$T/push"; mkdir -p "$PS"; PSN="$(native "$PS")"
pprobe() { verdict "$1" "$(hook "$2" | CORE_PUSH_LINT_HEAD=dddd444 CORE_PUSH_LINT_STAMPS="$PSN" CORE_MERGE_LINT_REFS="$REFS" CORE_MERGE_LINT_STAMPS="$TN" node "$G")" "$3"; }
pprobe "core branch push without a stamp" "git -C /tmp/wt push https://github.com/example-org/core.git fix/x:fix/x" block
: > "$PS/dddd444.ok"
pprobe "core branch push with a stamp" "git -C /tmp/wt push https://github.com/example-org/core.git fix/x:fix/x" allow
pprobe "a push to another repo is not gated" "git -C /tmp/wt push https://github.com/example-org/other.git fix/x" allow
rm "$PS/dddd444.ok"
: > "$PS/dddd444.fast.ok"
pprobe "a branch push with a fast stamp" "git -C /tmp/wt push https://github.com/example-org/core.git fix/x:fix/x" allow
pprobe "a train push with a fast stamp" "git -C /tmp/wt push https://github.com/example-org/core.git HEAD:refs/heads/train/2026-10-31-a" allow
rm "$PS/dddd444.fast.ok"
pprobe "the push named in a grep is no push" "grep -n 'git -C /tmp/wt push https://github.com/example-org/core.git' notes.md" allow
# A push by remote name from a fresh clone (2026-11-01): the remote's URL decides.
export CORE_PUSH_REMOTE_URL="https://github.com/example-org/core.git"
pprobe "a push by remote name to the core is gated" "git -C /tmp/wt push -u origin fix/x" block
pprobe "a bare push to the core is gated" "git -C /tmp/wt push -q" block
: > "$PS/dddd444.fast.ok"
pprobe "a push by remote name with a fast stamp" "git -C /tmp/wt push -u origin fix/x" allow
rm "$PS/dddd444.fast.ok"
export CORE_PUSH_REMOTE_URL="https://github.com/example-org/core-shared.git"
pprobe "a push to a repo whose name starts like the core's is not gated" "git -C /tmp/wt push origin main" allow
export CORE_PUSH_REMOTE_URL=""
pprobe "an unknown remote is not gated" "git -C /tmp/wt push nowhere x" allow
unset CORE_PUSH_REMOTE_URL
# The pushed branch, not HEAD (2026-11-02: a clone standing on main pushed another branch on main's stamp).
W="$T/wt"; git init -q -b main "$W"; WN="$(native "$W")"
git -C "$W" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
git -C "$W" branch feat/x
git -C "$W" -c user.email=t@t -c user.name=t commit -q --allow-empty -m two
MAIN=$(git -C "$W" rev-parse HEAD); FEAT=$(git -C "$W" rev-parse feat/x)
rprobe() { verdict "$1" "$(hook "$2" | CORE_PUSH_REMOTE_URL="https://github.com/example-org/core.git" CORE_PUSH_LINT_STAMPS="$PSN" node "$G")" "$3"; }
: > "$PS/$MAIN.fast.ok"
rprobe "a named branch other than HEAD, only HEAD stamped" "git -C $WN push -u origin feat/x" block
rprobe "the same push of HEAD itself" "git -C $WN push -u origin HEAD:refs/heads/main" allow
: > "$PS/$FEAT.fast.ok"
rprobe "the named branch stamped" "git -C $WN push -u origin feat/x" allow
[ $fail -eq 0 ] && echo "core-merge-lint-gate: all passed" || echo "core-merge-lint-gate: FAILED"
exit $fail
