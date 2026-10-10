#!/usr/bin/env bash
# covers: session-pull machine-profile machine-key
#
# Fixture for helpers/session-pull.sh, scripts/machine-profile.sh and scripts/machine-key.sh.
# Every property gets an input that must fire it and one that must stay silent. No network:
# every remote is a local bare repo, the one "dead network" remote is an ssh URL whose ssh
# command hangs.
#
# Usage: bash scripts/test-session-pull.sh   (exit 0 = all cases pass)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PULL="$HERE/../helpers/session-pull.sh"
PROFILE="$HERE/machine-profile.sh"
KEYSH="$HERE/machine-key.sh"
BOOTUP="$HERE/../helpers/session-bootup.sh"
fails=0
ok()    { echo "  ok   $1"; }
bad()   { echo "  FAIL $1 — $2"; fails=$((fails + 1)); }
has()   { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "missing [$2]" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "unexpected [$2]" ;; *) ok "$1" ;; esac; }
same()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "[$2] != [$3]"; fi; }
differ(){ if [ "$2" != "$3" ]; then ok "$1"; else bad "$1" "unchanged [$2]"; fi; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
# A path handed to a native process as DATA (env) must be in its form (os-traps OS-3).
native() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
git_q() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main -c protocol.file.allow=always "$@" >/dev/null 2>&1; }
head_of() { git -C "$1" rev-parse HEAD 2>/dev/null; }
n=0
# <name>: a bare remote $T/r/<name>.git and a working clone $T/w/<name> tracking main
mkrepo() {
  git_q init -q --bare "$T/r/$1.git"
  git_q clone -q "$T/r/$1.git" "$T/w/$1"
  echo seed > "$T/w/$1/seed.txt"
  git_q -C "$T/w/$1" add -A; git_q -C "$T/w/$1" commit -qm seed; git_q -C "$T/w/$1" push -q -u origin HEAD:main
}
# <name> [file]: one new upstream commit, pushed from a scratch clone
advance() {
  n=$((n + 1)); git_q clone -q "$T/r/$1.git" "$T/up$n"
  mkdir -p "$(dirname "$T/up$n/${2:-up.txt}")"; echo "$n" > "$T/up$n/${2:-up.txt}"
  git_q -C "$T/up$n" add -A; git_q -C "$T/up$n" commit -qm "up $n"; git_q -C "$T/up$n" push -q origin HEAD:main
}

# --- machine key --------------------------------------------------------------
echo "machine key:"
key=$(bash "$KEYSH")
case "$key" in ''|*[!a-z0-9_-]*) bad "key is a lowercase file-safe name" "[$key]" ;; *) ok "key is a lowercase file-safe name ($key)" ;; esac
if [ "$(uname -s)" = "Darwin" ] && command -v scutil >/dev/null 2>&1 && scutil --get LocalHostName >/dev/null 2>&1; then
  src=$(scutil --get LocalHostName); what="macOS: LocalHostName, not the network-dependent hostname"
else
  src=$(hostname); what="hostname"
fi
exp=$(printf '%s' "${src%%.*}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')
same "key comes from $what" "$key" "$exp"
same "sourced function and script agree" "$(. "$KEYSH"; machine_key)" "$key"

# --- machine profile ----------------------------------------------------------
echo "machine profile:"
B0="$T/pbrain"; mkdir -p "$B0"
out=$(bash "$PROFILE" "$B0" 2>&1)
same "no config/machines: silent (opt-in)" "$out" ""
mkdir -p "$B0/config/machines"
out=$(bash "$PROFILE" "$B0" 2>&1)
has "missing profile: one line naming the key" "!! machine: $key — no profile yet" "$out"
has "missing profile: the exact command to create it" "cp core/templates/machine-profile.md config/machines/$key.md" "$out"
has "no probe list: tools are 'not measured', not 'no'" "tools: not measured" "$out"
same "missing profile: exactly one line" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1"
sed -e 's/^- Alias:.*/- Alias: Studio box/' -e 's/^- Sender id:.*/- Sender id: op-studio/' \
  "$HERE/../templates/machine-profile.md" > "$B0/config/machines/$key.md"
printf '# probe list\ngit\nzz-no-such-tool-%s\n' "$$" > "$B0/config/machines/probe-tools.txt"
out=$(bash "$PROFILE" "$B0" 2>&1)
has "present profile: alias and sender id" "(alias Studio box, sender id op-studio)" "$out"
hasnt "present profile: no alarm" "!!" "$out"
has "tools measured live: present one" "tools on PATH: git" "$out"
has "tools measured live: absent one" "missing: zz-no-such-tool-$$" "$out"
out=$(CLAUDE_PROJECT_DIR="$B0" bash "$BOOTUP" 2>&1)
has "the session start carries the machine line" "machine: $key — profile config/machines/$key.md" "$out"

# --- session pull: setup --------------------------------------------------------
echo "session pull:"
mkdir -p "$T/r" "$T/w"
mkrepo brain; mkrepo core
BRAIN="$T/w/brain"
git_q -C "$BRAIN" submodule add -q "$T/r/core.git" core
git_q -C "$BRAIN" commit -qm "mount core"; git_q -C "$BRAIN" push -q origin HEAD:main
for r in clean dirty nobranch diverged extra; do mkrepo "$r"; done
git_q init -q --bare "$T/r/missing.git"; git_q clone -q "$T/r/missing.git" "$T/seedm"
echo m > "$T/seedm/m.txt"; git_q -C "$T/seedm" add -A; git_q -C "$T/seedm" commit -qm m; git_q -C "$T/seedm" push -q origin HEAD:main
advance clean; advance dirty; advance diverged; advance extra; advance core
advance brain docs/memory-snapshot/note.md
echo "local edit" > "$T/w/dirty/seed.txt"                     # tracked file, upstream does not touch it
git_q -C "$T/w/nobranch" checkout -q -b local-only
echo own > "$T/w/diverged/own.txt"; git_q -C "$T/w/diverged" add -A; git_q -C "$T/w/diverged" commit -qm own
mkdir -p "$BRAIN/config/machines"
printf '{"repos":{"brain":{"path":"%s","kind":"instance"},"core":{"path":"%s/core","kind":"core","remote":"%s"},"clean":{"path":"%s"},"dirty":{"path":"%s"},"nobranch":{"path":"%s"},"diverged":{"path":"%s"},"missing":{"path":"%s","remote":"%s"},"orphan":{"path":"%s"}}}\n' \
  "$BRAIN" "$BRAIN" "$T/r/core.git" "$T/w/clean" "$T/w/dirty" "$T/w/nobranch" "$T/w/diverged" \
  "$T/w/missing" "$T/r/missing.git" "$T/w/orphan" > "$BRAIN/config/ecosystem.json"
CFG_JSON=$(printf '{"ecosystem":true,"extra":[{"path":"%s"}],"stall_seconds":2,"budget_seconds":40}' "$T/w/extra")

h_clean=$(head_of "$T/w/clean"); h_dirty=$(head_of "$T/w/dirty"); h_div=$(head_of "$T/w/diverged")
h_core=$(head_of "$BRAIN/core"); h_brain=$(head_of "$BRAIN"); h_extra=$(head_of "$T/w/extra")
run_pull() { (cd "$BRAIN" && CLAUDE_PROJECT_DIR="$BRAIN" bash "${1:-$PULL}" >"$T/out" 2>"$T/err" </dev/null); echo $?; }

# opt-in: no config, nothing happens
rc=$(run_pull)
same "no config/session-pull.json: exit 0" "$rc" "0"
same "no config: silent" "$(cat "$T/err" "$T/out")" ""
same "no config: nothing pulled" "$(head_of "$T/w/clean")" "$h_clean"

# per-machine opt-out from the profile
printf '%s\n' "$CFG_JSON" > "$BRAIN/config/session-pull.json"
printf -- '- Alias: show box\n- Session pull: off\n' > "$BRAIN/config/machines/$key.md"
run_pull >/dev/null
has "profile 'Session pull: off': says so" "off on this machine" "$(cat "$T/err")"
same "profile 'Session pull: off': nothing pulled" "$(head_of "$T/w/clean")" "$h_clean"
rm -f "$BRAIN/config/machines/$key.md"

# the real run
rc=$(run_pull); err=$(cat "$T/err")
same "exit 0" "$rc" "0"
out=$(cat "$T/out")
# stdout reaches the session: the findings that need a look go there, the all-clear does not
has   "stdout: names the repos that need a look" "need a look" "$out"
has   "stdout: the dirty repo is in it" "dirty: uncommitted changes" "$out"
has   "stdout: the diverged repo is in it" "diverged (main): diverged" "$out"
hasnt "stdout: no all-clear lines (updated/cloned stay on stderr)" "updated" "$out"
same "clean repo behind upstream: fast-forwarded" "$(head_of "$T/w/clean")" "$(git -C "$T/r/clean.git" rev-parse main)"
has  "clean repo: one 'updated' line" "clean (main): updated" "$err"
same "dirty repo: HEAD untouched" "$(head_of "$T/w/dirty")" "$h_dirty"
same "dirty repo: the edit is still there" "$(cat "$T/w/dirty/seed.txt")" "local edit"
has  "dirty repo: reported" "dirty: uncommitted changes — not pulled" "$err"
has  "repo without upstream: skipped with a note" "nobranch: no upstream on 'local-only' — skipped" "$err"
same "diverged repo: HEAD untouched" "$(head_of "$T/w/diverged")" "$h_div"
has  "diverged repo: reported" "diverged (main): diverged — 1 local and 1 upstream" "$err"
same "missing repo with a remote: cloned" "$(head_of "$T/w/missing")" "$(git -C "$T/r/missing.git" rev-parse main)"
has  "missing repo: one 'cloned' line" "missing: cloned from" "$err"
has  "missing repo without a remote: skipped" "orphan: not checked out at" "$err"
same "core submodule: never pulled (its remote moved on)" "$(head_of "$BRAIN/core")" "$h_core"
hasnt "core submodule: no line at all" "core:" "$err"
differ "brain itself: fast-forwarded" "$(head_of "$BRAIN")" "$h_brain"
has  "brain: pull of the memory snapshot is named" "the pull changed docs/memory-snapshot" "$err"
differ "extra repo (not in ecosystem.json): fast-forwarded" "$(head_of "$T/w/extra")" "$h_extra"
has  "summary line" "done in" "$err"

# negative control on the second run: nothing behind any more, so no 'updated' line
run_pull >/dev/null
hasnt "second run: nothing left to update" "): updated" "$(cat "$T/err")"
has   "second run: the summary counts none" "0 updated" "$(cat "$T/err")"

# a dirty brain is not pulled
advance brain; h_brain=$(head_of "$BRAIN")
echo x >> "$BRAIN/seed.txt"
run_pull >/dev/null
same "dirty brain: not pulled" "$(head_of "$BRAIN")" "$h_brain"
has  "dirty brain: reported" "brain: uncommitted changes" "$(cat "$T/err")"
git -C "$BRAIN" checkout -q -- seed.txt

# dead network: a remote that never answers costs the stall limit, not the session start
git_q clone -q "$T/r/clean.git" "$T/w/hang"
git -C "$T/w/hang" remote set-url origin "ssh://hang.invalid/x.git"
printf '#!/bin/sh\nsleep 20\n' > "$T/hang.sh"
# stall 4 > budget 3: the hang alone spends the budget, so the second repo is not reached;
# the brain step before it stays far below 3 s.
printf '{"ecosystem":false,"extra":[{"path":"%s"},{"path":"%s"}],"stall_seconds":4,"budget_seconds":3}\n' \
  "$T/w/hang" "$T/w/clean" > "$BRAIN/config/session-pull.json"
t0=$SECONDS
(cd "$BRAIN" && CLAUDE_PROJECT_DIR="$BRAIN" GIT_SSH_COMMAND="sh $(native "$T/hang.sh")" bash "$PULL" >/dev/null 2>"$T/err" </dev/null)
dt=$((SECONDS - t0))
has "hanging remote: reported after the stall limit" "hang: fetch failed — no answer within 4s" "$(cat "$T/err")"
if [ "$dt" -lt 12 ]; then ok "hanging remote: run ended in ${dt}s (stall 4 s, not the 20 s hang)"; else bad "hanging remote: run took ${dt}s" "stall limit not applied"; fi
has "run budget: the rest is named, not silently dropped" "1 not reached (budget 3s spent)" "$(cat "$T/err")"

# negative control: a variant WITHOUT the dirty guard must fail the dirty case above —
# proof that the case has teeth (the upstream commit does not touch the edited file, so
# git itself would happily fast-forward).
sed '/status --porcelain --untracked-files=no/,/^  fi$/d' "$PULL" > "$T/broken-pull.sh"
printf '%s\n' "$CFG_JSON" > "$BRAIN/config/session-pull.json"
advance dirty; h_dirty=$(head_of "$T/w/dirty")
run_pull "$T/broken-pull.sh" >/dev/null
differ "negative control: without the dirty guard the dirty repo IS pulled" "$(head_of "$T/w/dirty")" "$h_dirty"

echo
if [ "$fails" -eq 0 ]; then echo "session-pull fixtures: ALL passed"; else echo "session-pull fixtures: $fails FAILED"; fi
[ "$fails" -eq 0 ]
