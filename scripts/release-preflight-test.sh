#!/usr/bin/env bash
# Fixture tests for release-preflight.sh — both directions per detector discipline:
# every check proven to FAIL on its defect and to PASS when clean. Runs against a
# throwaway git repo (RELEASE_PREFLIGHT_ROOT), never against this checkout.
set -u

S="$(cd "$(dirname "$0")" && pwd)/release-preflight.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
OLD="$(date -u -v-2d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "2 days ago" +%Y-%m-%dT%H:%M:%SZ)"
# readiness checks 6-9 (2026-10-25, check 6 reworked 2026-10-28): every case below names a
# consumer and uses an EMPTY shared-memory fixture, so only the case that breaks a readiness
# check sees it red
SHM="$TMP/shared"; mkdir -p "$SHM/core"
export RELEASE_CONSUMER="fixture consumer" SHARED_MEMORY_REPO="$SHM" RELEASE_TOPIC=core
# Each preflight run writes here, and a failing check prints it: on 2026-10-28 two cases failed
# once on ubuntu-latest (rc=1 for 0) and the log held only the summary line, so the cause could
# not be read.
LAST="$TMP/last-run.out"; : > "$LAST"
# a gh stub first on PATH for every case (check 6 fails closed without a readable gh); it answers
# from files: gh-label (does the label beta-candidate exist: 1/0), gh-cand (open beta-candidate
# PR numbers), gh-open (any open PR numbers), proof.txt (pr view), gh-down (beta-candidate
# queries fail). Case 10 runs on the real PATH on purpose.
REALPATH="$PATH"
GHDEF="$TMP/gh-default"; mkdir -p "$GHDEF"
printf '#!/usr/bin/env bash
d="%s"
case "$*" in
  *beta-candidate*) [ -e "$d/gh-down" ] && exit 1
    case "$*" in *"label list"*) cat "$d/gh-label";; *) cat "$d/gh-cand";; esac ;;
  *isDraft*) cat "$d/gh-open" ;;
  *"pr view"*) n="${*#*pr view }"; n="${n%% *}"; if [ -f "$d/proof-$n.txt" ]; then cat "$d/proof-$n.txt"; else cat "$d/proof.txt"; fi ;;
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
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }  # OS-3
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
{ b64 'instance-key: abc — checked on macOS'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "a merged PR with only the macOS proof fails" 1 $?
{ b64 'instance-key: abc — macOS OK'; b64 'instance-key: def — Windows check OK'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "both OS proofs with instance keys pass" 0 $?
{ b64 'instance-key: abc — macOS OK'; b64 'Windows OK too, no key'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "OS words without an instance key do not count" 1 $?
# 2026-10-28: a line that names Windows only as still open is no Windows proof (#156-#159 carried
# "macOS: OK at <sha> ... Windows check still open." — the old word test counted it for both).
{ b64 'instance-key: abc — macOS: OK at abc1234. Windows check still open.'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "Windows named only as open is no Windows proof" 1 $?
# 2026-11-04 (macOS instance): a merge train's thread carries the merger's own OK only - its MEMBERS carry the
# proofs; a text whose first line names the CI job is no proof; both proofs from one instance are one review.
{ b64 '<!-- instance-key: abc -->
## Merge train train/x

Contains (each PR branch head, merged unchanged):
- #8 fix/y abc1234

Left out:
- #9 (conflicts with the train so far)'; b64 'instance-key: abc — macOS OK at the train head'; b64 'instance-key: def — Windows OK'; } > "$TMP/proof-7.txt"
{ b64 'instance-key: abc — macOS OK'; } > "$TMP/proof-8.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "a train is judged by its members: the member without a Windows proof fails" 1 $?
rm -f "$TMP/proof-7.txt" "$TMP/proof-8.txt"
{ b64 'instance-key: abc — macOS OK'; b64 'instance-key: def — CI at this head: 16 checks OK including portability on macOS and Windows'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "a comment naming the Windows CI job is no Windows proof" 1 $?
{ b64 'instance-key: abc — macOS OK at head 627d2db (measured once): CI 16 checks none failing including portability on macOS and Windows'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "one instance naming both systems is one review, not two (#399, 2026-11-04)" 1 $?
# the author's own test line with a negative control in brackets is a Windows proof (#376, 2026-11-04)
{ b64 'instance-key: abc — **Test (Windows, Git Bash):** `scripts/test-x.sh` all cases pass (two new — both FAIL against `origin/main`); done.'; b64 'instance-key: def — macOS OK at head'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >"$LAST" 2>&1
check "a negative-control clause in the author test line does not cancel its Windows proof" 0 $?

echo
echo "$pass/$((pass+fail)) passed"
[ "$fail" -eq 0 ]
