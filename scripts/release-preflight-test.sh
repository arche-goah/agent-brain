#!/usr/bin/env bash
# Fixture tests for release-preflight.sh — both directions per detector discipline:
# every check proven to FAIL on its defect and to PASS when clean. Runs against a
# throwaway git repo (RELEASE_PREFLIGHT_ROOT), never against this checkout.
set -u

S="$(cd "$(dirname "$0")" && pwd)/release-preflight.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$(cd "$(dirname "$0")" && pwd)/git-sandbox.sh"   # the host's git hooks must not decide the fixture's pushes (2026-11-06)
pass=0; fail=0
OLD="$(date -u -v-2d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "2 days ago" +%Y-%m-%dT%H:%M:%SZ)"
# readiness checks 6-9 (2026-10-25, check 6 reworked 2026-10-28): every case below names a
# consumer and uses an EMPTY shared-memory fixture, so only the case that breaks a readiness
# check sees it red
SHM="$TMP/shared"; mkdir -p "$SHM/core"
export RELEASE_CONSUMER="fixture consumer" SHARED_MEMORY_REPO="$SHM" RELEASE_TOPIC=core
# The fixture repos commit and push: no git config or hook of the host machine may reach them
# (git-sandbox.sh: temp global config, no system config, no prompt, no askpass). Paths that
# cross into a native program as DATA are stated natively (OS-3).
. "$(dirname "$0")/git-sandbox.sh"
git config --global init.defaultBranch main
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
# check 10 (real-data replay, 2026-11-06): every case gets a fake brain and a reader whose output
# never changes, so only the case that breaks check 10 sees it red
mkdir -p "$TMP/replay-brain"
printf '{"readers": [{"name": "constant", "argv": ["python3", "-c", "print(1)"]}]}\n' > "$TMP/readers-const.json"
export RELEASE_REPLAY_BRAIN="$TMP/replay-brain" RELEASE_REPLAY_READERS="$TMP/readers-const.json"
# check 11 (release scope, 2026-11-06): every case gets a brain with an open scope for 2.0.0, an instance id in its
# settings env, no ledgers and no open PR, so only the case that breaks check 11 sees it red. The PR list is a file
# python opens as DATA (OS-3: native path).
mkscope() { # mkscope <brain dir> <version> <items JSON list>
  mkdir -p "$1/.claude-state" "$1/.claude"
  printf '{"env": {"SHARED_MEMORY_SELF": "fixture-self"}}\n' > "$1/.claude/settings.json"
  printf '{"version": "%s", "repo": "agent-brain", "status": "open", "items": %s, "excluded": {}}\n' "$2" "$3" \
    > "$1/.claude-state/release-scope.json"
}
mkscope "$TMP/scope-brain" 2.0.0 '[]'
printf '[]\n' > "$TMP/prs-none.json"
export RELEASE_SCOPE_BRAIN="$TMP/scope-brain" RELEASE_SCOPE_PR_FIXTURE="$(native "$TMP/prs-none.json")"
# the instance id comes from the fixture brain's settings, never from the session that runs this fixture (measured
# 2026-11-06: an exported SHARED_MEMORY_SELF of the running session gave another key, and the own-PR case read green)
unset SHARED_MEMORY_SELF
# Each preflight run writes here, and a failing check prints it: on 2026-10-28 two cases failed
# once on ubuntu-latest (rc=1 for 0) and the log held only the summary line, so the cause could
# not be read.
LAST="$TMP/last-run.out"; : > "$LAST"
# a gh stub first on PATH for every case (check 6 fails closed without a readable gh); it answers
# from files: gh-label (does the label beta-candidate exist: 1/0), gh-cand (open beta-candidate
# PR numbers), gh-open (any open PR numbers), proof.txt (pr view), gh-down (beta-candidate
# queries fail). Case 10 runs on the real PATH on purpose. The PR number is cut from "$*" copied
# into a variable (`${*#…}` cuts each argument on its own) and the stub is written by printf (a
# literal `%%` is spelled `%%%%`): both slips together left the number unparsed, and every
# `proof-<n>.txt` was ignored for proof.txt (measured 2026-11-06, macOS instance).
REALPATH="$PATH"
GHDEF="$TMP/gh-default"; mkdir -p "$GHDEF"
printf '#!/usr/bin/env bash
d="%s"
case "$*" in
  *beta-candidate*) [ -e "$d/gh-down" ] && exit 1
    case "$*" in *"label list"*) cat "$d/gh-label";; *) cat "$d/gh-cand";; esac ;;
  *isDraft*) cat "$d/gh-open" ;;
  *"pr view"*) a="$*"; n="${a#*pr view }"; n="${n%%%% *}"; if [ -f "$d/proof-$n.txt" ]; then cat "$d/proof-$n.txt"; else cat "$d/proof.txt"; fi ;;
  *) echo 0 ;;
esac
' "$TMP" > "$GHDEF/gh"
chmod +x "$GHDEF/gh"
echo 1 > "$TMP/gh-label"; : > "$TMP/gh-cand"; : > "$TMP/gh-open"; : > "$TMP/proof.txt"
export PATH="$GHDEF:$PATH"
check() { # check <name> <expected-rc> <actual-rc>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1";
  else fail=$((fail+1)); echo "FAIL $1 (expected rc=$2, got rc=$3)"; sed 's/^/      | /' "$LAST" | tail -15; fi
}

mkrepo() { # fresh repo with manifest+changelog at version $1, origin = bare twin
  # mktemp, not $RANDOM: two cases drawing the same number share a repo, and a case that moved
  # main (readiness check 6) then fails the next one — the 2026-10-28 pattern exactly.
  local ver="$1" d; d="$(mktemp -d "$TMP/repo-XXXXXX")"
  mkdir -p "$d/.claude-plugin"
  printf '{"name":"brain-core","version":"%s"}\n' "$ver" > "$d/.claude-plugin/plugin.json"
  printf '# Changelog\n\n## %s — 2026-01-01\n\n- entry\n' "$ver" > "$d/CHANGELOG.md"
  git -C "$d" init --quiet -b main
  git -C "$d" -c user.email=t@t -c user.name=t add -A
  # two days old (a commit age no check depends on since 2026-10-28; kept for stable fixtures)
  GIT_COMMITTER_DATE="$OLD" GIT_AUTHOR_DATE="$OLD" git -C "$d" -c user.email=t@t -c user.name=t commit --quiet -m init
  git init --quiet --bare "$d-origin.git"
  git -C "$d" remote add origin "$d-origin.git"
  git -C "$d" push --quiet -u origin main
  echo "$d"
}

# 1. clean local preflight -> PASS (gh check may be a note, never a fail here)
R="$(mkrepo 2.0.0)"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "clean local preflight passes" 0 $?

# 2. manifest mismatch -> FAIL (the v1.2.0 class)
R="$(mkrepo 1.9.9)"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "manifest != tag fails" 1 $?

# 3. missing CHANGELOG section -> FAIL
R="$(mkrepo 2.0.0)"
printf '# Changelog\n\n## 1.0.0\n' > "$R/CHANGELOG.md"
GIT_COMMITTER_DATE="$OLD" GIT_AUTHOR_DATE="$OLD" git -C "$R" -c user.email=t@t -c user.name=t commit --quiet -am strip
git -C "$R" push --quiet origin main
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "missing changelog section fails" 1 $?

# 4. tag already exists -> FAIL (race guard)
R="$(mkrepo 2.0.0)"
git -C "$R" tag v2.0.0 && git -C "$R" push --quiet origin v2.0.0
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "existing tag fails" 1 $?

# 5. tag only on ORIGIN (other session released) -> FAIL after fetch
R="$(mkrepo 2.0.0)"
git -C "$R-origin.git" tag v2.0.0 HEAD 2>/dev/null || git -C "$R" push --quiet origin main:refs/tags/v2.0.0
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "remote-only tag fails (fetch works)" 1 $?

# 6. HEAD differs from origin/main -> FAIL
R="$(mkrepo 2.0.0)"
git -C "$R" -c user.email=t@t -c user.name=t commit --quiet --allow-empty -m local-only
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "HEAD != origin/main fails" 1 $?

# 7. CI mode ignores git state, checks content only -> PASS on clean content
R="$(mkrepo 2.0.0)"
git -C "$R" tag v2.0.0   # existing tag must NOT matter in ci mode
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" --ci-tag v2.0.0 >"$LAST" 2>&1
check "ci mode passes on clean content" 0 $?

# 8. CI mode catches the manifest mismatch -> FAIL
R="$(mkrepo 1.1.2)"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" --ci-tag v1.2.0 >"$LAST" 2>&1
check "ci mode catches the v1.2.0 class" 1 $?

# 9. malformed tag argument -> usage error rc=2
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" 2.0.0 >"$LAST" 2>&1
check "malformed tag rejected" 2 $?

# 10. check 5 asks the repo UNDER TEST, not the caller's checkout: started from this
#     (GitHub) checkout against a fixture whose origin is a bare local repo, gh must not
#     answer — a green "no competing open release PR" here is the caller's repo speaking.
R="$(mkrepo 2.0.0)"
OUT="$(cd "$(dirname "$S")" && PATH="$REALPATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 2>&1)"
case "$OUT" in *"no competing open release PR"*) rc=1;; *) rc=0;; esac
check "release-PR check queries the repo under test" 0 $rc

# 10b. the same property without network or login (review alex-macos on #155): with an
#      unauthenticated gh both the old and the fixed script print "?", so 10 alone cannot
#      tell them apart. A stub gh first on PATH records where it was started; it must be $R.
STUB="$TMP/gh-stub"; mkdir -p "$STUB"
printf '#!/usr/bin/env bash
pwd -P > "%s/gh-cwd"
echo 0
' "$TMP" > "$STUB/gh"
chmod +x "$STUB/gh"
rm -f "$TMP/gh-cwd"
(cd "$(dirname "$S")" && PATH="$STUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1)
[ "$(cat "$TMP/gh-cwd" 2>/dev/null)" = "$(cd "$R" && pwd -P)" ] && rc=0 || rc=1
check "gh runs inside the repo under test (stub, network-free)" 0 $rc

# 11. a fragment left in changelog.d/ -> FAIL; README.md there is no fragment -> PASS (ci mode,
#     content only, so the git state of the fixture does not matter)
R="$(mkrepo 2.0.0)"
mkdir -p "$R/changelog.d"; printf 'how to\n' > "$R/changelog.d/README.md"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" --ci-tag v2.0.0 >"$LAST" 2>&1
check "changelog.d with only README passes" 0 $?
printf -- '- **forgotten.** (test: T0)\n' > "$R/changelog.d/forgotten.md"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" --ci-tag v2.0.0 >"$LAST" 2>&1
check "a fragment left in changelog.d fails" 1 $?

# 12. an entry still under ## Unreleased -> FAIL; an empty ## Unreleased header -> PASS
R="$(mkrepo 2.0.0)"
printf '# Changelog\n\n## Unreleased\n\n## 2.0.0 — 2026-01-01\n\n- entry\n' > "$R/CHANGELOG.md"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" --ci-tag v2.0.0 >"$LAST" 2>&1
check "empty Unreleased header passes" 0 $?
printf '# Changelog\n\n## Unreleased\n\n- not released\n\n## 2.0.0 — 2026-01-01\n\n- entry\n' > "$R/CHANGELOG.md"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" --ci-tag v2.0.0 >"$LAST" 2>&1
check "an entry under Unreleased fails" 1 $?

# 13. after a real cut by changelog-assemble.py the leftover check is green (the round trip)
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
R="$(mkrepo 2.1.0)"
printf '# Changelog\n\n## 2.0.0 — 2026-01-01\n\n- entry\n' > "$R/CHANGELOG.md"
mkdir -p "$R/changelog.d"; printf -- '- **new.** (test: T0)\n' > "$R/changelog.d/new.md"
"$PY" "$(native "$(dirname "$S")/changelog-assemble.py")" 2.1.0 --root "$(native "$R")" >/dev/null 2>&1
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" --ci-tag v2.1.0 >"$LAST" 2>&1
check "preflight green after a real changelog-assemble cut" 0 $?

# 14. readiness, check 6 (operator correction 2026-10-28: a beta waits for an important
#     candidate still in work, not for a quiet main): an open PR labelled beta-candidate -> FAIL
#     naming it; none -> PASS; an unrelated open PR and a fresh commit on main no longer fail;
#     gh unreadable -> FAIL (closed); the label not existing, said explicitly by gh -> PASS;
#     the operator's quoted word waives a candidate, a paraphrase does not
R="$(mkrepo 2.0.0)"
git -C "$R" -c user.email=t@t -c user.name=t commit --quiet --allow-empty -m fresh
git -C "$R" push --quiet origin main
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "a fresh commit on main no longer fails" 0 $?
echo 12 > "$TMP/gh-open"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "an unrelated open PR no longer fails" 0 $?
: > "$TMP/gh-open"
echo 42 > "$TMP/gh-cand"
OUT="$(RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 2>&1)"; rc=$?; printf '%s\n' "$OUT" > "$LAST"
case "$OUT" in *"FAIL"*"#42"*) named=0;; *) named=1;; esac
check "an open beta-candidate PR fails and is named" 1 $(( rc * (1 - named) ))
RELEASE_PREFLIGHT_ROOT="$R" RELEASE_EARLY_OK='operator 2026-10-25 "cut it today"' bash "$S" v2.0.0 >"$LAST" 2>&1
check "the operator's quoted word with a date waives the candidate" 0 $?
RELEASE_PREFLIGHT_ROOT="$R" RELEASE_EARLY_OK='the operator said it is fine' bash "$S" v2.0.0 >"$LAST" 2>&1
check "a paraphrase without quote and date does not waive" 1 $?
: > "$TMP/gh-cand"
touch "$TMP/gh-down"
OUT="$(RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 2>&1)"; rc=$?; printf '%s\n' "$OUT" > "$LAST"
case "$OUT" in *"FAIL"*"beta-candidate"*) said=0;; *) said=1;; esac
check "gh unreadable fails closed" 1 $(( rc * (1 - said) ))
rm -f "$TMP/gh-down"
echo 0 > "$TMP/gh-label"
OUT="$(RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 2>&1)"; rc=$?; printf '%s\n' "$OUT" > "$LAST"
case "$OUT" in *"does not exist"*) said=0;; *) said=1;; esac
check "label absent (gh says so) counts as no candidate, and is said" 0 $(( rc + said ))
echo 1 > "$TMP/gh-label"

# 15. readiness, check 7: an open shared-memory entry under the topic that this release waits for
#     (it names an open PR of the repo, or the version) -> FAIL; any other open entry is named, not
#     counted (agreed 2026-11-02: two old requests to an instance that builds no release held a tag);
#     closed -> PASS; no clone -> a note, not red
R="$(mkrepo 2.0.0)"
printf -- '---\nname: x\nmetadata:\n  status: open\n---\nPR #7 follows\n' > "$SHM/core/request-x.md"
echo 7 > "$TMP/gh-open"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "an open shared-memory entry naming an open PR fails" 1 $?
: > "$TMP/gh-open"
OUT="$(RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 2>&1)"; rc=$?; printf '%s\n' "$OUT" > "$LAST"
case "$OUT" in *"none awaited by this release"*"request-x"*) said=0;; *) said=1;; esac
check "the same entry once its PR is closed: named, not counted" 0 $(( rc + said ))
printf -- '---\nname: y\nmetadata:\n  status: open\n---\nwaits for another instance, nothing for a release\n' > "$SHM/core/request-y.md"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "an open entry with no PR and no version does not hold the release" 0 $?
printf -- '---\nname: z\nmetadata:\n  status: open\n---\nthe Windows check for v2.0.0 is still to come\n' > "$SHM/core/request-z.md"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "an open entry naming the version being cut fails" 1 $?
printf -- '---\nname: z\nmetadata:\n  status: open\n---\nother-suite#7 and 12.0.0 are not ours\n' > "$SHM/core/request-z.md"
mv "$SHM/core/request-x.md" "$TMP/request-x.md"
echo 7 > "$TMP/gh-open"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "another repo's #7 and a longer version are not this release's" 0 $?
mv "$TMP/request-x.md" "$SHM/core/request-x.md"
: > "$TMP/gh-open"; rm -f "$SHM/core/request-y.md" "$SHM/core/request-z.md"
echo 7 > "$TMP/gh-open"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "control: the PR-naming entry blocks again while #7 is open" 1 $?
: > "$TMP/gh-open"
sed -i.bak 's/status: open/status: answered/' "$SHM/core/request-x.md" && rm -f "$SHM/core/request-x.md.bak"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "the same entry answered passes" 0 $?
OUT="$(RELEASE_PREFLIGHT_ROOT="$R" SHARED_MEMORY_REPO="$TMP/no-such-shared" bash "$S" v2.0.0 2>&1)"; rc=$?
case "$OUT" in *"NOT run"*) said=0;; *) said=1;; esac
check "no shared-memory clone: said, not red" 0 $(( rc + said ))
rm -f "$SHM/core/request-x.md"
# 15b. the topic comes from the origin URL, not the folder name (2026-11-02: a worktree named
#      `train-212` skipped check 7): folder `repo-XXXX`, origin `.../agent-brain.git`, no RELEASE_TOPIC
R="$(mkrepo 2.0.0)"
mkdir -p "$TMP/named-$$"; git init --quiet --bare "$TMP/named-$$/agent-brain.git"
git -C "$R" remote set-url origin "$TMP/named-$$/agent-brain.git"
git -C "$R" push --quiet -u origin main
printf -- '---\nname: y\nmetadata:\n  status: open\n---\nPR follows for v2.0.0\n' > "$SHM/core/request-y.md"
RELEASE_TOPIC= RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1; rc=$?
grep -q "under core/" "$LAST" || rc=99
check "a worktree with another folder name still reads the topic from its origin URL" 1 $rc
rm -f "$SHM/core/request-y.md"

# 16. readiness, check 9: no consumer named -> FAIL
R="$(mkrepo 2.0.0)"
RELEASE_PREFLIGHT_ROOT="$R" RELEASE_CONSUMER= bash "$S" v2.0.0 >"$LAST" 2>&1
check "no consumer named fails" 1 $?

# 17. readiness, check 8: a PR merged since the previous tag without both OS proofs -> FAIL;
#     with both (instance key + the OS words) -> PASS. gh is the default stub (proof.txt).
R="$(mkrepo 2.0.0)"
git -C "$R" tag v1.9.0
GIT_COMMITTER_DATE="$OLD" GIT_AUTHOR_DATE="$OLD" git -C "$R" -c user.email=t@t -c user.name=t commit --quiet --allow-empty -m "Merge pull request #7 from o/x"
git -C "$R" push --quiet origin main v1.9.0
GHSTUB="$GHDEF"
# the stub answers like gh with `@base64`: one base64 line per text (body, comments)
b64() { printf '%s' "$1" | base64 | tr -d '\n'; echo; }
{ b64 '<!-- instance-key: abc --> checked on macOS'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "a merged PR with only the macOS proof fails" 1 $?
{ b64 '<!-- instance-key: abc --> macOS OK'; b64 '<!-- instance-key: def --> Windows check OK'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "both OS proofs with instance keys pass" 0 $?
{ b64 '<!-- instance-key: abc --> macOS OK'; b64 'Windows OK too, no key'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "OS words without an instance key do not count" 1 $?
# 2026-10-28: a line that names Windows only as still open is no Windows proof (#156-#159 carried
# "macOS: OK at <sha> ... Windows check still open." — the old word test counted it for both).
{ b64 '<!-- instance-key: abc --> macOS: OK at abc1234. Windows check still open.'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "Windows named only as open is no Windows proof" 1 $?
# 2026-11-04 (macOS instance): a merge train's thread carries the merger's own OK only - its MEMBERS carry the
# proofs; a text whose first line names the CI job is no proof; both proofs from one instance are one review.
{ b64 '<!-- instance-key: abc -->
## Merge train train/x

Contains (each PR branch head, merged unchanged):
- #8 fix/y abc1234

Left out:
- #9 (conflicts with the train so far)'; b64 '<!-- instance-key: abc --> macOS OK at the train head'; b64 '<!-- instance-key: def --> Windows OK'; } > "$TMP/proof-7.txt"
{ b64 '<!-- instance-key: abc --> macOS OK'; } > "$TMP/proof-8.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "a train is judged by its members: the member without a Windows proof fails" 1 $?
rm -f "$TMP/proof-7.txt" "$TMP/proof-8.txt"
{ b64 '<!-- instance-key: abc --> macOS OK'; b64 '<!-- instance-key: def --> CI at this head: 16 checks OK including portability on macOS and Windows'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "a comment naming the Windows CI job is no Windows proof" 1 $?
{ b64 '<!-- instance-key: abc --> macOS OK at head 627d2db (measured once): CI 16 checks none failing including portability on macOS and Windows'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "one instance naming both systems is one review, not two (#399, 2026-11-04)" 1 $?
# the author's own test line with a negative control in brackets is a Windows proof (#376, 2026-11-04)
{ b64 '<!-- instance-key: abc --> **Test (Windows, Git Bash):** `scripts/test-x.sh` all cases pass (two new — both FAIL against `origin/main`); done.'; b64 '<!-- instance-key: def --> macOS OK at head'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "a negative-control clause in the author test line does not cancel its Windows proof" 0 $?
: > "$TMP/proof.txt"

# 18. check 10, real-data replay (operator decision 2026-11-06): no brain = red and said "NOT run";
#     a reader whose output differs between the previous tag and HEAD = red; RELEASE_REPLAY_OK names
#     what was reviewed and passes with a note; a failing symptom line of this version's entry = red.
#     Runs on its own repo and gives $R back at the end: a later section builds on the repo before it
#     (measured 2026-11-06 in a merge train - the failing symptom left behind here turned two OS-review
#     cases of the next section red at check 10, not at their own subject).
R_BEFORE_REPLAY="$R"
R="$(mkrepo 2.0.0)"
OUT="$(RELEASE_PREFLIGHT_ROOT="$R" RELEASE_REPLAY_BRAIN= bash "$S" v2.0.0 2>&1)"; rc=$?; printf '%s\n' "$OUT" > "$LAST"
case "$OUT" in *"FAIL real-data replay NOT run: no real data"*) said=0;; *) said=1;; esac
check "no real brain: check 10 is red and says NOT run" 1 $(( rc * (1 - said) ))
printf 'old\n' > "$R/reader.txt"; git -C "$R" add -A; git -C "$R" commit --quiet -m reader; git -C "$R" tag v1.9.0
printf 'new\n' > "$R/reader.txt"; git -C "$R" commit --quiet -am "reader changed"
git -C "$R" push --quiet origin main v1.9.0
printf '{"readers": [{"name": "fixture", "argv": ["python3", "-c", "import sys; print(open(sys.argv[1]).read())", "{core}/reader.txt"]}]}\n' > "$TMP/readers-diff.json"
OUT="$(RELEASE_PREFLIGHT_ROOT="$R" RELEASE_REPLAY_READERS="$TMP/readers-diff.json" bash "$S" v2.0.0 2>&1)"; rc=$?; printf '%s\n' "$OUT" > "$LAST"
case "$OUT" in *"FAIL real-data replay: the readers"*"+new"*|*"+new"*"FAIL real-data replay: the readers"*) said=0;; *) said=1;; esac
check "a reader differing from the previous tag on real data is red, with the diff" 1 $(( rc * (1 - said) ))
OUT="$(RELEASE_PREFLIGHT_ROOT="$R" RELEASE_REPLAY_READERS="$TMP/readers-diff.json" RELEASE_REPLAY_OK="fixture diff read" bash "$S" v2.0.0 2>&1)"; rc=$?; printf '%s\n' "$OUT" > "$LAST"
case "$OUT" in *"reviewed: fixture diff read"*) said=0;; *) said=1;; esac
check "RELEASE_REPLAY_OK passes the difference and names what was reviewed" 0 $(( rc + said ))
printf '# Changelog\n\n## 2.0.0 — 2026-01-01\n\n- **fix.** (test: T1)\n  symptom: python3 -c "import sys; sys.exit(4)" <!-- fragment: fix -->\n' > "$R/CHANGELOG.md"
git -C "$R" commit --quiet -am "symptom"; git -C "$R" push --quiet origin main
OUT="$(RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 2>&1)"; rc=$?; printf '%s\n' "$OUT" > "$LAST"
case "$OUT" in *"FAILS    symptom"*"rc=4"*) said=0;; *) said=1;; esac
check "a failing symptom line of this version's entry is red" 1 $(( rc * (1 - said) ))
R="$R_BEFORE_REPLAY"

# 18. ONE reader (helpers/os-review.cjs), measured 2026-11-06 on the macOS instance for release v2.1.3: the three
#     macOS OKs check 8 rejected and the two PR bodies an instance-side report counted as macOS reviews, each text as
#     it stood in the thread (keys replaced, one Windows OK from another key next to it). The allow cases are red
#     against the old reader; the negatives must name "no macOS".
WIN_OK="$(b64 '<!-- instance-key: def --> **Windows OK at head 3c60b9b** (the Windows instance, measured once)')"
os_case() { # os_case <label> <expect-rc> <text>; the thread of #7 is <text> plus WIN_OK
  { b64 "$3"; printf '%s\n' "$WIN_OK"; } > "$TMP/proof.txt"
  OUT="$(PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 2>&1)"; rc=$?; printf '%s\n' "$OUT" > "$LAST"
  if [ "$2" = 1 ]; then case "$OUT" in *"#7(no macOS)"*) ;; *) rc=99;; esac; fi
  check "$1" "$2" "$rc"
}
os_case "#414: a compound word (red-free) is no fail word" 0 '<!-- instance-key: abc -->
**macOS OK at head `3c60b9b`** (the macOS instance, 2026-11-05, measured once): `core-push-lint` GREEN (ci-lint-local 13 steps, 1 skipped), `scripts/brain-friction-test.py` 14/14 (new case 8 red-free both directions in one tree), branch scanner against the instance'"'"'s brain: `blind-to-indirection` gone. CI green (14 checks). Windows: requested by hand for train 2.1.3 (os:windows).'
os_case "#332: a word in the evidence after the verdict (the open entries) does not cancel it" 0 '<!-- instance-key: abc -->
macOS OK at head 2f6e54f — the macOS instance ran `bash scripts/workflow-parse-check.sh` (5 workflows loadable) and `bash scripts/test-workflow-relays.sh` (all checks passed) at this head, and read the diff of `workflows/coherence-scan.js` and `workflows/full-audit-synthesis.js`: prompt text only — read the open entries first, a matching one gets a "seen again <date>" line instead of a new entry, `appended` counts new entries only. The counting contract (`appended_orders` / `appended`) stays a returned number; no schema change. No finding.'
os_case "#382: a first line that says macOS OK is no CI note, though it also names the CI" 0 '**macOS OK at head `2cf2960`** (the macOS instance, 2026-11-04, measured once): read the diff at this head — the two findings of the first macOS review are taken (#7 named "in its conditional part only" in the carrier line and the priority list; the uncarried clauses rank with item 3; the fragment says so). CI at this head: every check SUCCESS or SKIPPED (`gh pr view --json statusCheckRollup`, read 2026-11-04). Joins today'"'"'s merge train; the train'"'"'s Windows job is the Windows evidence.

<!-- instance-key: abc -->'
os_case "#342: a PR body with a key, the word macOS and a pass word is no macOS review" 1 '## Why

Measured 2026-11-02 on the macOS instance: an interactive turn closed on "Next: package A …" while the operator had released that plan in the same session. The word-pattern stop gates missed the sentence, and the operator decided against adding more word lists — the check has to read state, not wording.

## Fixture

Result: **38/38** green on this branch. Negative control (`IDLE_GATE=<main build> bash scripts/test-autonomous-idle-gate.sh`): the main-branch gate fails **5** of them (every new block case), all 25 earlier cases unchanged.

- Holds **once per turn**: the re-issue after its block (`stop_hook_active`) passes.

<!-- instance-key: abc -->'
os_case "#386: the same for a body that says the incident let a check pass" 1 '<!-- instance-key: abc -->
## Why

Agreed with the operator on 2026-11-03 (question tool). Measured on the macOS instance the same day: a review comment claimed "read the diff of `scripts/open-items.py`" while the only diff read before it was another PR'"'"'s, on the same file.

## Replay

Over every transcript of this brain: 8 posts with such a claim; the gate holds exactly the measured incident. The first version ("any diff since the previous post") let the incident pass and, reading `api-request-blob` lines as calls, made four false holds — both fixed before this PR.'
os_case "a key in prose without the comment marker is no key" 1 'instance-key: abc — macOS OK at head 3c60b9b'
os_case "a merger's OK without an OS is no review" 1 '<!-- instance-key: abc --> OK at head 3c60b9b, merging'

# 19. a hand review on the TRAIN thread at the train head covers every member (merge-train.sh asks the OS checks once,
#     for the train head; measured 2026-11-06: without it every member needed its own request). Negative controls: a
#     train review that names another OS does not cover the missing one, and one that names no head covers nobody.
TRAIN='<!-- instance-key: abc -->
## Merge train train/x

Base: main @ 1111111 · train head: abc1234

Contains (each PR'"'"'s branch head, merged unchanged):
- #8 fix/y 8888888
- #9 fix/z 9999999'
train_case() { # train_case <label> <expect-rc> <expect-in-output|-> <train review texts...>
  local label="$1" want="$2" said="$3"; shift 3
  { b64 "$TRAIN"; for t in "$@"; do b64 "$t"; done; } > "$TMP/proof-7.txt"
  OUT="$(PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 2>&1)"; rc=$?; printf '%s\n' "$OUT" > "$LAST"
  if [ "$said" != - ]; then case "$OUT" in *"$said"*) ;; *) rc=99;; esac; fi
  check "$label" "$want" "$rc"
}
{ b64 '<!-- instance-key: abc --> macOS OK at head `8888888`'; } > "$TMP/proof-8.txt"
: > "$TMP/proof-9.txt"
train_case "a train review per OS at the train head covers every member" 0 - \
  '<!-- instance-key: abc --> **macOS OK at head `abc1234`, by hand** (the macOS instance, measured once)' \
  '<!-- instance-key: def --> **Windows OK at head abc1234, by hand** (the Windows instance, measured once)'
train_case "a train review naming another OS does not cover the missing one" 1 "#8(no Windows)" \
  '<!-- instance-key: def --> **macOS OK at head abc1234, by hand** (the Windows instance read it on a Mac)'
train_case "a train review that names no head covers nobody" 1 "#9(neither)" \
  '<!-- instance-key: abc --> macOS OK at the train head' '<!-- instance-key: def --> Windows OK at the train head'
rm -f "$TMP/proof-7.txt" "$TMP/proof-8.txt" "$TMP/proof-9.txt"

# 20. check 11, the release scope (operator 2026-11-06): no brain = red and said "NOT run"; an own open PR outside the
#     scope = red and named, in the scope = green; an own branch with commits not on origin/main = red and named; a
#     scope for another version = red. Runs on its own repo and brain and gives $R back as it found it (a section that
#     leaks its repo turns the next one red, measured 2026-11-06).
R_BEFORE_SCOPE="$R"
R="$(mkrepo 2.0.0)"
OUT="$(RELEASE_PREFLIGHT_ROOT="$R" RELEASE_SCOPE_BRAIN= bash "$S" v2.0.0 2>&1)"; rc=$?; printf '%s\n' "$OUT" > "$LAST"
case "$OUT" in *"FAIL release scope NOT run: no brain"*) said=0;; *) said=1;; esac
check "no scope brain: check 11 is red and says NOT run" 1 $(( rc * (1 - said) ))
SKEY="$("$PY" -c 'import sys; sys.path.insert(0, sys.argv[1]); import instance_key; print(instance_key.key_for("fixture-self"))' "$(native "$(dirname "$S")")")"
printf '[{"number": 5, "headRefName": "feat/own", "title": "own", "body": "<!-- instance-key: %s -->"}]\n' "$SKEY" > "$TMP/prs-own.json"
OUT="$(RELEASE_PREFLIGHT_ROOT="$R" RELEASE_SCOPE_PR_FIXTURE="$(native "$TMP/prs-own.json")" bash "$S" v2.0.0 2>&1)"; rc=$?; printf '%s\n' "$OUT" > "$LAST"
case "$OUT" in *"OPEN PR agent-brain#5"*"FAIL release scope 2.0.0"*) said=0;; *) said=1;; esac
check "an own open PR outside the scope is red and named" 1 $(( rc * (1 - said) ))
mkscope "$TMP/scope-brain-pr" 2.0.0 '["agent-brain#5"]'
RELEASE_PREFLIGHT_ROOT="$R" RELEASE_SCOPE_BRAIN="$TMP/scope-brain-pr" RELEASE_SCOPE_PR_FIXTURE="$(native "$TMP/prs-own.json")" bash "$S" v2.0.0 >"$LAST" 2>&1
check "the same PR in the scope passes" 0 $?
git -C "$R" branch feat/unshipped
git -C "$R" -c user.email=t@t -c user.name=t commit --quiet --allow-empty -m wip
git -C "$R" branch -f feat/unshipped HEAD
git -C "$R" reset --quiet --hard origin/main
OUT="$(RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 2>&1)"; rc=$?; printf '%s\n' "$OUT" > "$LAST"
case "$OUT" in *"OPEN branch feat/unshipped"*) said=0;; *) said=1;; esac
check "an own branch with commits not on origin/main is red and named" 1 $(( rc * (1 - said) ))
git -C "$R" branch -q -D feat/unshipped
mkscope "$TMP/scope-brain-old" 1.9.9 '[]'
OUT="$(RELEASE_PREFLIGHT_ROOT="$R" RELEASE_SCOPE_BRAIN="$TMP/scope-brain-old" bash "$S" v2.0.0 2>&1)"; rc=$?; printf '%s\n' "$OUT" > "$LAST"
case "$OUT" in *"the scope is for 1.9.9, this release is 2.0.0"*) said=0;; *) said=1;; esac
check "a scope for another version is red" 1 $(( rc * (1 - said) ))
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "control: the same repo, branch gone, clean scope passes" 0 $?
R="$R_BEFORE_SCOPE"

echo
echo "$pass/$((pass+fail)) passed"
[ "$fail" -eq 0 ]
