#!/usr/bin/env bash
# covers: pr-ball session-bootup
# test-pr-ball.sh — the bootup line "PR waiting on you" must fire for a move that is really
# the viewer's and stay silent for everything else. Synthetic GraphQL JSON, fixed clock,
# no network.
#
# WHY (2026-09-15): a changes-requested review on a collaborator's core PR sat two days
# without a reply. Both sides' session starts named the open PRs and the new shared-memory
# commits — newness, not obligation — so each side believed it was waiting on the other.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BALL="$ROOT/scripts/pr-ball.py"
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
[ -f "$BALL" ] || { bad "pr-ball.py not found"; exit 1; }

NOW="2026-09-15T08:00:00Z"   # 40 h after 2026-09-13T16:00Z
run() { printf '%s' "$2" | "$PY" "$BALL" --now "$NOW"; }
expect_line() { # $1 label, $2 json, $3 substring that must appear
  out="$(run "$1" "$2")"
  case "$out" in *"$3"*) ok "$1" ;; *) bad "$1 — got: ${out:-<silence>}" ;; esac
}
expect_silent() { # $1 label, $2 json
  out="$(run "$1" "$2")"
  [ -z "$out" ] && ok "$1" || bad "$1 — expected silence, got: $out"
}
pr() { # $1 viewer, $2 one PR node
  printf '{"data":{"viewer":{"login":"%s"},"search":{"nodes":[%s]}}}' "$1" "$2"
}

# 1. the measured case, from the author's side: changes requested after the last commit
expect_line "author: changes requested after the last commit, 40 h" \
  "$(pr author '{"number":143,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"Author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T15:00:00Z"}}]},"reviews":{"nodes":[{"author":{"login":"maint"},"state":"CHANGES_REQUESTED","submittedAt":"2026-09-13T16:00:00Z"}]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')" \
  "core#143 yours - changes requested, 40 h"

# 2. the author answered with a commit: the move went back, silence
expect_silent "author: a commit after the review hands the move back" \
  "$(pr author '{"number":143,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T17:00:00Z"}}]},"reviews":{"nodes":[{"author":{"login":"maint"},"state":"CHANGES_REQUESTED","submittedAt":"2026-09-13T16:00:00Z"}]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')"

# 3. the reviewer's side: new commits after my last review
expect_line "reviewer: new commits after my review, 40 h" \
  "$(pr maint '{"number":143,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T16:00:00Z"}}]},"reviews":{"nodes":[{"author":{"login":"maint"},"state":"CHANGES_REQUESTED","submittedAt":"2026-09-13T10:00:00Z"}]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')" \
  "core#143 review - new commits since your last look"

# 4. asked by @-mention in the body (the only channel before write access), case-insensitive
expect_line "reviewer: @-mentioned in the body, never looked" \
  "$(pr Reviewer '{"number":145,"isDraft":false,"body":"review/OK please @REVIEWER","repository":{"name":"core"},"author":{"login":"maint"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T16:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')" \
  "core#145 review - asked, not looked at yet"

# 5. a comment by me after the last commit counts as a look
expect_silent "reviewer: my comment after the last commit is a look" \
  "$(pr reviewer '{"number":145,"isDraft":false,"body":"@reviewer","repository":{"name":"core"},"author":{"login":"maint"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T16:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[{"author":{"login":"reviewer"},"createdAt":"2026-09-13T18:00:00Z"}]},"reviewRequests":{"nodes":[]}}')"

# 6. not involved at all: someone else's PR in a suite they lead — not my move
expect_silent "bystander: foreign PR without review, request or mention" \
  "$(pr maint '{"number":112,"isDraft":false,"body":"fix","repository":{"name":"suite"},"author":{"login":"lead"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-09T12:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')"

# 7. a formal review request is an ask too, without any mention in the body
expect_line "reviewer: a formal review request fires without a mention" \
  "$(pr reviewer '{"number":7,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"maint"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T16:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[{"requestedReviewer":{"login":"reviewer"}}]}}')" \
  "core#7 review - asked"

# 8. under 24 h: a fresh move is normal work, not a stall
expect_silent "fresh: a move open for 2 h stays silent" \
  "$(pr author '{"number":9,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-15T05:00:00Z"}}]},"reviews":{"nodes":[{"author":{"login":"maint"},"state":"CHANGES_REQUESTED","submittedAt":"2026-09-15T06:00:00Z"}]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')"

# 9. drafts never count
expect_silent "draft: never a move" \
  "$(pr author '{"number":10,"isDraft":true,"body":"","repository":{"name":"core"},"author":{"login":"author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T15:00:00Z"}}]},"reviews":{"nodes":[{"author":{"login":"maint"},"state":"CHANGES_REQUESTED","submittedAt":"2026-09-13T16:00:00Z"}]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')"

# 10. offline / gh error: no JSON on stdin is silence, exit 0
out="$(printf '' | "$PY" "$BALL" --now "$NOW")"; rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] && ok "no input: silence and exit 0" || bad "no input: rc=$rc out=$out"

# 12. the line is pure ASCII, separator included. Measured 2026-09-15 on the Windows
#     runner: Python prints through the console code page there, and an em dash in the
#     line arrived as a replacement character — on a collaborator's Windows bootup too,
#     not only in this fixture. Two moves, so the separator is in the output.
out="$(run two "$(pr author '{"number":1,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T15:00:00Z"}}]},"reviews":{"nodes":[{"author":{"login":"maint"},"state":"CHANGES_REQUESTED","submittedAt":"2026-09-13T16:00:00Z"}]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}},{"number":2,"isDraft":false,"body":"@author","repository":{"name":"core"},"author":{"login":"maint"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T16:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')")"
if [ -n "$out" ] && LC_ALL=C awk '/[^\t -~]/ { bad = 1 } END { exit bad }' <<EOF
$out
EOF
then ok "two moves in one line, all ASCII: $out"
else bad "line empty or not pure ASCII (breaks on a Windows code page): ${out:-<silence>}"
fi

# 11. the bootup actually calls it (a carrier without a trigger is no carrier)
if grep -q 'scripts/pr-ball.py' "$ROOT/helpers/session-bootup.sh"; then
  ok "session-bootup.sh calls pr-ball.py"
else
  bad "session-bootup.sh does not call pr-ball.py — the line would never appear"
fi

[ "$fail" -eq 0 ] && echo "test-pr-ball: all checks passed"
exit "$fail"
