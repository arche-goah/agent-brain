#!/usr/bin/env bash
# covers: core-push-lint
# Fixture for the queue in scripts/core-push-lint.sh: two runs at once never lint in parallel, a stamped commit is
# not linted again, a dead owner's lock is taken over, a commit that lands while a run waits gets no stamp.
# Ported 2026-11-17 from the instance where the script ran as an alpha (the script came with #565, its fixture did not).
# Usage: bash scripts/test-core-push-lint-queue.sh (exit 0 = pass)
set -u
S="$(cd "$(dirname "$0")" && pwd)/core-push-lint.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
W="$T/wt"; mkdir -p "$W/scripts"
# A stand-in lint: records start and end, takes 2 s.
printf '%s\n' '#!/usr/bin/env bash' 'echo "start $(date +%s)" >> "$LOG"; sleep 2; echo "end $(date +%s)" >> "$LOG"; echo "ci-lint-local: 1 of 1 ok"' > "$W/scripts/ci-lint-local.sh"
git -C "$W" init -q; git -C "$W" add -A; git -C "$W" -c user.name=t -c user.email=t@t commit -qm x
export LOG="$T/log" CORE_PUSH_LINT_STAMPS="$T/stamps" CORE_PUSH_LINT_LOCK="$T/stamps/.lock"
# Two runs at once on the same commit: one lints, the other waits and takes its stamp.
bash "$S" "$W" > "$T/a" 2>&1 & pa=$!
sleep 0.5
bash "$S" "$W" > "$T/b" 2>&1 & pb=$!
wait "$pa"; ra=$?; wait "$pb"; rb=$?
starts=$(grep -c '^start' "$LOG")
[ "$ra" -eq 0 ] && [ "$rb" -eq 0 ] && ok "both runs end green" || bad "rc a=$ra b=$rb"
[ "$starts" -eq 1 ] && ok "the commit was linted once, not twice" || bad "linted $starts times: $(cat "$T/a" "$T/b")"
grep -q "queued behind\|stamped by the run ahead\|already stamped" "$T/b" && ok "the second run says it waited or reused" || bad "second run: $(cat "$T/b")"
# A stamped commit is not linted again.
bash "$S" "$W" > "$T/c" 2>&1
[ "$(grep -c '^start' "$LOG")" -eq 1 ] && grep -q "already stamped" "$T/c" && ok "a stamped commit is reused" || bad "re-linted: $(cat "$T/c")"
# A lock left by a dead process is taken over.
git -C "$W" -c user.name=t -c user.email=t@t commit -q --allow-empty -m y
mkdir -p "$CORE_PUSH_LINT_LOCK"; echo 999999 > "$CORE_PUSH_LINT_LOCK/pid"
bash "$S" "$W" > "$T/d" 2>&1; rd=$?
[ "$rd" -eq 0 ] && [ "$(grep -c '^start' "$LOG")" -eq 2 ] && ok "a dead owner's lock is taken over" || bad "dead lock: rc=$rd $(cat "$T/d")"
[ ! -d "$CORE_PUSH_LINT_LOCK" ] && ok "the lock is released at the end" || bad "lock left behind"
# A commit lands while the run waits for the lock (2026-11-03): no stamp for the old sha over the new files.
git -C "$W" -c user.name=t -c user.email=t@t commit -q --allow-empty -m z
old="$(git -C "$W" rev-parse HEAD)"
mkdir -p "$CORE_PUSH_LINT_LOCK"; sleep 30 & holder=$!; echo "$holder" > "$CORE_PUSH_LINT_LOCK/pid"
bash "$S" "$W" > "$T/e" 2>&1 & pe=$!
sleep 1; git -C "$W" -c user.name=t -c user.email=t@t commit -q --allow-empty -m moved
kill "$holder" 2>/dev/null; wait "$pe"; re=$?
[ "$re" -eq 2 ] && grep -q "moved while queued" "$T/e" && [ ! -f "$CORE_PUSH_LINT_STAMPS/$old.ok" ] && ok "HEAD moved while queued: exit 2, no stamp for the old sha" \
  || bad "moved while queued: rc=$re $(cat "$T/e")"
echo
[ "$fail" -eq 0 ] && echo "core-push-lint queue: all cases pass" || echo "core-push-lint queue: FAILURES"
exit "$fail"
