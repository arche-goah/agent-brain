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
# readiness checks 6-10 (2026-10-25): every case below names a consumer and uses an EMPTY
# shared-memory fixture, so only the case that breaks a readiness check sees it red
SHM="$TMP/shared"; mkdir -p "$SHM/core"
export RELEASE_CONSUMER="fixture consumer" SHARED_MEMORY_REPO="$SHM" RELEASE_TOPIC=core
check() { # check <name> <expected-rc> <actual-rc>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1";
  else fail=$((fail+1)); echo "FAIL $1 (expected rc=$2, got rc=$3)"; fi
}

mkrepo() { # fresh repo with manifest+changelog at version $1, origin = bare twin
  local ver="$1" d="$TMP/repo-$RANDOM"
  mkdir -p "$d/.claude-plugin"
  printf '{"name":"brain-core","version":"%s"}\n' "$ver" > "$d/.claude-plugin/plugin.json"
  printf '# Changelog\n\n## %s — 2026-01-01\n\n- entry\n' "$ver" > "$d/CHANGELOG.md"
  git -C "$d" init --quiet -b main
  git -C "$d" -c user.email=t@t -c user.name=t add -A
  # two days old: check 6 (quiet main) is green unless a case moves main on purpose
  GIT_COMMITTER_DATE="$OLD" GIT_AUTHOR_DATE="$OLD" git -C "$d" -c user.email=t@t -c user.name=t commit --quiet -m init
  git init --quiet --bare "$d-origin.git"
  git -C "$d" remote add origin "$d-origin.git"
  git -C "$d" push --quiet -u origin main
  echo "$d"
}

# 1. clean local preflight -> PASS (gh check may be a note, never a fail here)
R="$(mkrepo 2.0.0)"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >/dev/null 2>&1
check "clean local preflight passes" 0 $?

# 2. manifest mismatch -> FAIL (the v1.2.0 class)
R="$(mkrepo 1.9.9)"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >/dev/null 2>&1
check "manifest != tag fails" 1 $?

# 3. missing CHANGELOG section -> FAIL
R="$(mkrepo 2.0.0)"
printf '# Changelog\n\n## 1.0.0\n' > "$R/CHANGELOG.md"
GIT_COMMITTER_DATE="$OLD" GIT_AUTHOR_DATE="$OLD" git -C "$R" -c user.email=t@t -c user.name=t commit --quiet -am strip
git -C "$R" push --quiet origin main
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >/dev/null 2>&1
check "missing changelog section fails" 1 $?

# 4. tag already exists -> FAIL (race guard)
R="$(mkrepo 2.0.0)"
git -C "$R" tag v2.0.0 && git -C "$R" push --quiet origin v2.0.0
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >/dev/null 2>&1
check "existing tag fails" 1 $?

# 5. tag only on ORIGIN (other session released) -> FAIL after fetch
R="$(mkrepo 2.0.0)"
git -C "$R-origin.git" tag v2.0.0 HEAD 2>/dev/null || git -C "$R" push --quiet origin main:refs/tags/v2.0.0
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >/dev/null 2>&1
check "remote-only tag fails (fetch works)" 1 $?

# 6. HEAD differs from origin/main -> FAIL
R="$(mkrepo 2.0.0)"
git -C "$R" -c user.email=t@t -c user.name=t commit --quiet --allow-empty -m local-only
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >/dev/null 2>&1
check "HEAD != origin/main fails" 1 $?

# 7. CI mode ignores git state, checks content only -> PASS on clean content
R="$(mkrepo 2.0.0)"
git -C "$R" tag v2.0.0   # existing tag must NOT matter in ci mode
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" --ci-tag v2.0.0 >/dev/null 2>&1
check "ci mode passes on clean content" 0 $?

# 8. CI mode catches the manifest mismatch -> FAIL
R="$(mkrepo 1.1.2)"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" --ci-tag v1.2.0 >/dev/null 2>&1
check "ci mode catches the v1.2.0 class" 1 $?

# 9. malformed tag argument -> usage error rc=2
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" 2.0.0 >/dev/null 2>&1
check "malformed tag rejected" 2 $?

# 10. check 5 asks the repo UNDER TEST, not the caller's checkout: started from this
#     (GitHub) checkout against a fixture whose origin is a bare local repo, gh must not
#     answer — a green "no competing open release PR" here is the caller's repo speaking.
R="$(mkrepo 2.0.0)"
OUT="$(cd "$(dirname "$S")" && RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 2>&1)"
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
(cd "$(dirname "$S")" && PATH="$STUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >/dev/null 2>&1)
[ "$(cat "$TMP/gh-cwd" 2>/dev/null)" = "$(cd "$R" && pwd -P)" ] && rc=0 || rc=1
check "gh runs inside the repo under test (stub, network-free)" 0 $rc

# 11. a fragment left in changelog.d/ -> FAIL; README.md there is no fragment -> PASS (ci mode,
#     content only, so the git state of the fixture does not matter)
R="$(mkrepo 2.0.0)"
mkdir -p "$R/changelog.d"; printf 'how to\n' > "$R/changelog.d/README.md"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" --ci-tag v2.0.0 >/dev/null 2>&1
check "changelog.d with only README passes" 0 $?
printf -- '- **forgotten.** (test: T0)\n' > "$R/changelog.d/forgotten.md"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" --ci-tag v2.0.0 >/dev/null 2>&1
check "a fragment left in changelog.d fails" 1 $?

# 12. an entry still under ## Unreleased -> FAIL; an empty ## Unreleased header -> PASS
R="$(mkrepo 2.0.0)"
printf '# Changelog\n\n## Unreleased\n\n## 2.0.0 — 2026-01-01\n\n- entry\n' > "$R/CHANGELOG.md"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" --ci-tag v2.0.0 >/dev/null 2>&1
check "empty Unreleased header passes" 0 $?
printf '# Changelog\n\n## Unreleased\n\n- not released\n\n## 2.0.0 — 2026-01-01\n\n- entry\n' > "$R/CHANGELOG.md"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" --ci-tag v2.0.0 >/dev/null 2>&1
check "an entry under Unreleased fails" 1 $?

# 13. after a real cut by changelog-assemble.py the leftover check is green (the round trip)
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
R="$(mkrepo 2.1.0)"
printf '# Changelog\n\n## 2.0.0 — 2026-01-01\n\n- entry\n' > "$R/CHANGELOG.md"
mkdir -p "$R/changelog.d"; printf -- '- **new.** (test: T0)\n' > "$R/changelog.d/new.md"
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }  # OS-3
"$PY" "$(native "$(dirname "$S")/changelog-assemble.py")" 2.1.0 --root "$(native "$R")" >/dev/null 2>&1
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" --ci-tag v2.1.0 >/dev/null 2>&1
check "preflight green after a real changelog-assemble cut" 0 $?

# 14. readiness, check 6: a commit on main younger than the floor -> FAIL; the operator's
#     word (quote + date) waives it; a paraphrase without quote marks or date does not
R="$(mkrepo 2.0.0)"
git -C "$R" -c user.email=t@t -c user.name=t commit --quiet --allow-empty -m fresh
git -C "$R" push --quiet origin main
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >/dev/null 2>&1
check "main moved within the floor fails (the strand still collects)" 1 $?
RELEASE_PREFLIGHT_ROOT="$R" RELEASE_EARLY_OK='operator 2026-10-25 "cut it today"' bash "$S" v2.0.0 >/dev/null 2>&1
check "the operator's quoted word with a date waives the floor" 0 $?
RELEASE_PREFLIGHT_ROOT="$R" RELEASE_EARLY_OK='the operator said it is fine' bash "$S" v2.0.0 >/dev/null 2>&1
check "a paraphrase without quote and date does not waive" 1 $?
RELEASE_PREFLIGHT_ROOT="$R" RELEASE_QUIET_HOURS=0 bash "$S" v2.0.0 >/dev/null 2>&1
check "a floor of 0 h accepts a fresh main (the knob works)" 0 $?

# 15. readiness, check 8: an open shared-memory entry under the topic -> FAIL; closed -> PASS;
#     no clone -> a note, not red
R="$(mkrepo 2.0.0)"
printf -- '---\nname: x\nmetadata:\n  status: open\n---\nPR follows\n' > "$SHM/core/request-x.md"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >/dev/null 2>&1
check "an open shared-memory entry under the topic fails" 1 $?
sed -i.bak 's/status: open/status: answered/' "$SHM/core/request-x.md" && rm -f "$SHM/core/request-x.md.bak"
RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >/dev/null 2>&1
check "the same entry answered passes" 0 $?
OUT="$(RELEASE_PREFLIGHT_ROOT="$R" SHARED_MEMORY_REPO="$TMP/no-such-shared" bash "$S" v2.0.0 2>&1)"; rc=$?
case "$OUT" in *"NOT run"*) said=0;; *) said=1;; esac
check "no shared-memory clone: said, not red" 0 $(( rc + said ))
rm -f "$SHM/core/request-x.md"

# 16. readiness, check 10: no consumer named -> FAIL
R="$(mkrepo 2.0.0)"
RELEASE_PREFLIGHT_ROOT="$R" RELEASE_CONSUMER= bash "$S" v2.0.0 >/dev/null 2>&1
check "no consumer named fails" 1 $?

# 17. readiness, check 9: a PR merged since the previous tag without both OS proofs -> FAIL;
#     with both (instance key + the OS words) -> PASS. gh is a stub answering from a file.
R="$(mkrepo 2.0.0)"
git -C "$R" tag v1.9.0
GIT_COMMITTER_DATE="$OLD" GIT_AUTHOR_DATE="$OLD" git -C "$R" -c user.email=t@t -c user.name=t commit --quiet --allow-empty -m "Merge pull request #7 from o/x"
git -C "$R" push --quiet origin main v1.9.0
GHSTUB="$TMP/gh-proof"; mkdir -p "$GHSTUB"
# check 5 asks for a count (release PRs), check 7 for a list of numbers (isDraft in the query)
printf '#!/usr/bin/env bash\ncase "$*" in *isDraft*) echo "";; *"pr list"*) echo 0;; *"pr view"*) cat "%s/proof.txt";; *) echo 0;; esac\n' "$TMP" > "$GHSTUB/gh"
chmod +x "$GHSTUB/gh"
# the stub answers like gh with `@base64`: one base64 line per text (body, comments)
b64() { printf '%s' "$1" | base64 | tr -d '\n'; echo; }
{ b64 'instance-key: abc — checked on macOS'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >/dev/null 2>&1
check "a merged PR with only the macOS proof fails" 1 $?
{ b64 'instance-key: abc — macOS OK'; b64 'instance-key: def — Windows check OK'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >/dev/null 2>&1
check "both OS proofs with instance keys pass" 0 $?
{ b64 'instance-key: abc — macOS OK'; b64 'Windows OK too, no key'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >/dev/null 2>&1
check "OS words without an instance key do not count" 1 $?
# 2026-10-28: a line that names Windows only as still open is no Windows proof (#156-#159 carried
# "macOS: OK at <sha> ... Windows check still open." — the old word test counted it for both).
{ b64 'instance-key: abc — macOS: OK at abc1234. Windows check still open.'; } > "$TMP/proof.txt"
PATH="$GHSTUB:$PATH" RELEASE_PREFLIGHT_ROOT="$R" bash "$S" v2.0.0 >/dev/null 2>&1
check "Windows named only as open is no Windows proof" 1 $?

echo
echo "$pass/$((pass+fail)) passed"
[ "$fail" -eq 0 ]
