#!/usr/bin/env bash
# covers: pre-commit
# Fixture for the "behind the upstream" check of helpers/git-hooks/pre-commit (operator order
# 2026-10-22, agreed by both core parties) — both directions, sandbox repos only (a bare remote
# and two clones), no network.
# Must refuse: a clone another clone pushed past. Must pass: after the pull, ahead only, no
# upstream, detached HEAD, the switch off, a merge being concluded, an unreachable remote, and a
# fetch slower than the timeout (fail-open, inside the time limit).
# Exit 0 = all pass.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../helpers/git-hooks/pre-commit"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0; checks=0
ok()  { checks=$((checks + 1)); echo "  ok   $1"; }
bad() { checks=$((checks + 1)); fails=$((fails + 1)); echo "  FAIL $1 — $2"; }
# The host's global hooks (core.hooksPath) must not run inside the sandbox: the fixture calls the
# hook under test itself.
mkdir -p "$T/nohooks"
g() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main -c core.autocrlf=false \
        -c core.hooksPath="$T/nohooks" "$@"; }
gq() { g "$@" >/dev/null 2>&1; }
hook() { (cd "$1" && bash "$HOOK" 2>&1); }   # prints the hook's output, returns its rc
refuses() { local o; o=$(hook "$2"); [[ $? -ne 0 && "$o" == *"$3"* ]] && ok "$1" || bad "$1" "rc/out: $o"; }
passes()  { local o; o=$(hook "$2"); [[ $? -eq 0 ]] && ok "$1" || bad "$1" "refused: $o"; }

gq init -q --bare "$T/remote.git"
gq clone -q "$T/remote.git" "$T/a"
echo seed > "$T/a/f.txt"; gq -C "$T/a" add -A; gq -C "$T/a" commit -qm seed; gq -C "$T/a" push -q -u origin HEAD:main
gq -C "$T/a" branch -q --set-upstream-to=origin/main
gq clone -q "$T/remote.git" "$T/b"

echo "behind: another clone pushed"
echo other > "$T/b/g.txt"; gq -C "$T/b" add -A; gq -C "$T/b" commit -qm "pushed from the other machine"; gq -C "$T/b" push -q origin HEAD:main
echo local > "$T/a/h.txt"; gq -C "$T/a" add -A
refuses "a clone behind its upstream is refused" "$T/a" "is behind origin/main by 1 commit(s)"
refuses "  ... and the missing commit is listed" "$T/a" "pushed from the other machine"
refuses "  ... and the way out is named" "$T/a" "git pull --ff-only"
[[ ! -f "$T/a/g.txt" ]] && ok "  ... and the hook pulled nothing" || bad "the hook pulled" "g.txt arrived"

echo "pass cases"
gq -C "$T/a" stash -q; gq -C "$T/a" pull -q --ff-only; gq -C "$T/a" stash pop -q
passes "after the pull" "$T/a"
gq -C "$T/a" commit -qm "local only"
echo more >> "$T/a/h.txt"; gq -C "$T/a" add -A
passes "ahead only (a local commit not yet pushed)" "$T/a"
gq -C "$T/a" commit -qm "local two"; gq -C "$T/a" push -q origin HEAD:main
echo again > "$T/b/g.txt"; gq -C "$T/b" pull -q --no-rebase; gq -C "$T/b" add -A; gq -C "$T/b" commit -qm "second push"; gq -C "$T/b" push -q origin HEAD:main
gq -C "$T/a" checkout -q -b topic
passes "a branch without upstream" "$T/a"
gq -C "$T/a" checkout -q main
gq -C "$T/a" checkout -q --detach
passes "detached HEAD" "$T/a"
gq -C "$T/a" checkout -q main
gq -C "$T/a" config brain.preCommitFetch false
passes "switched off for this repo (while behind)" "$T/a"
gq -C "$T/a" config --unset brain.preCommitFetch
refuses "  ... and on again, behind is refused" "$T/a" "is behind origin/main"

echo "a merge being concluded"
gq -C "$T/a" reset -q --hard
echo mine > "$T/a/g.txt"; gq -C "$T/a" add -A; gq -C "$T/a" commit -qm "conflicting local"
gq -C "$T/a" pull -q --no-rebase 2>/dev/null   # conflicts on g.txt
git -C "$T/a" rev-parse -q --verify MERGE_HEAD >/dev/null && ok "  (setup: merge in progress)" || bad "setup" "no MERGE_HEAD"
echo resolved > "$T/a/g.txt"; gq -C "$T/a" add -A
passes "concluding the merge that brings the upstream in" "$T/a"
gq -C "$T/a" commit -q --no-edit

echo "fail-open on the network"
echo x >> "$T/b/g.txt"; gq -C "$T/b" pull -q --no-rebase; gq -C "$T/b" add -A; gq -C "$T/b" commit -qm third; gq -C "$T/b" push -q origin HEAD:main
gq -C "$T/a" fetch -q   # a knows it is behind; the remote then goes away
gq -C "$T/a" remote set-url origin "$T/gone.git"
o=$(hook "$T/a"); rc=$?
[[ $rc -eq 0 ]] && ok "an unreachable remote does not block" || bad "unreachable remote" "rc $rc: $o"
[[ "$o" == *"fetch of 'origin' failed"* ]] && ok "  ... and says the check was skipped" || bad "skip note" "$o"
# A remote that never answers: git's ext transport runs a command that only sleeps.
gq -C "$T/a" config protocol.ext.allow always
gq -C "$T/a" remote set-url origin "ext::sh -c sleep% 10"
s=$(date +%s); o=$(PRE_COMMIT_FETCH_TIMEOUT=1 hook "$T/a"); rc=$?; e=$(( $(date +%s) - s ))
[[ $rc -eq 0 ]] && ok "a fetch slower than the timeout does not block" || bad "slow fetch" "rc $rc: $o"
[[ $e -le 8 ]] && ok "  ... and the hook returns within the limit (${e}s for 1 s)" || bad "slow fetch time" "${e}s"
[[ "$o" == *"took over 1 s"* ]] && ok "  ... and says the check was skipped" || bad "timeout note" "$o"

echo
if [[ $fails -eq 0 ]]; then echo "test-pre-commit-behind: all $checks checks passed"; exit 0; fi
echo "test-pre-commit-behind: $fails of $checks checks FAILED"; exit 1
