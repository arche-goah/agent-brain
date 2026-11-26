#!/usr/bin/env bash
# Fixture: core-push-lint.sh refuses a commit whose author carries a watch-listed name, before the long lint;
# a commit under the neutral identity passes that step (and then meets the lint, which this fixture stubs).
# Why (2026-11-04): two core PRs from a fresh scratch clone went red in the CI step "leak scan (commits)" — the
# clone committed under the global git identity; the local scan had no watch list and said 0 findings.
# Ported 2026-11-17 from the instance where the script ran as an alpha (the script came with #565, its fixture did not).
# Usage: bash scripts/test-core-push-lint-identity.sh   (exit 0 = both cases pass)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
# a fake core repo: origin/main + one commit; leak-scan.py and a stub ci-lint-local.sh copied from the real core
mkdir -p "$T/repo/scripts" "$T/stamps"
cp "$HERE/leak-scan.py" "$T/repo/scripts/leak-scan.py"
printf '#!/usr/bin/env bash\necho "ci-lint-local: all 0 step(s) passed (stub)"\n' > "$T/repo/scripts/ci-lint-local.sh"
git -C "$T/repo" init -q -b main
git -C "$T/repo" -c user.name=arche-goah -c user.email=151987871+arche-goah@users.noreply.github.com add -A
git -C "$T/repo" -c user.name=arche-goah -c user.email=151987871+arche-goah@users.noreply.github.com commit -q -m "base"
git -C "$T/repo" update-ref refs/remotes/origin/main HEAD
printf '{"names": ["Watched Person"], "instances": []}\n' > "$T/names.json"
run() { # name, author name, expect RED|GREEN
  git -C "$T/repo" reset -q --hard refs/remotes/origin/main      # each case: one commit on top of origin/main
  echo "x" >> "$T/repo/file.txt"
  git -C "$T/repo" -c "user.name=$2" -c user.email=151987871+arche-goah@users.noreply.github.com add file.txt
  git -C "$T/repo" -c "user.name=$2" -c user.email=151987871+arche-goah@users.noreply.github.com commit -q -m "change"
  local out; out="$(CORE_PUSH_LINT_STAMPS="$T/stamps" CORE_PUSH_LINT_NAMES="$T/names.json" bash "$HERE/core-push-lint.sh" --fast "$T/repo" 2>&1)"
  case "$out" in *"core-push-lint: $3"*) echo "  OK  $1";; *) echo "  FAIL $1 (got: ${out:0:200})"; fail=1;; esac
}
run "author carries a watch-listed name -> RED before the lint" "Watched Person" RED
run "neutral identity -> passes the commit scan (stub lint GREEN)" "arche-goah" GREEN
[ "$fail" = 0 ] && echo "core-push-lint-identity: all cases pass" || { echo "core-push-lint-identity: FAILURES"; exit 1; }
