#!/usr/bin/env bash
# covers: repo-activity-watch.sh repo-activity-filter.py
# Fixture for the repo-activity watch with a fake `gh` on PATH — no network, no real repos.
#
# Must-report cases (each one a channel a real watch was once blind to): a comment on an
# already MERGED pull request, an inline review comment, a new PR, a merge of our PR by the
# other party, and a comment under the operator's OWN account (the other own machine).
# Negative controls prove the checks can fail: an author filter on the own login must make
# the own-account case disappear, a shared cursor between two watches must swallow the
# slower watch's event, and nothing may repeat in the second round.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$HERE/repo-activity-watch.sh"
fails=0; checks=0
ok()    { checks=$((checks + 1)); }
bad()   { checks=$((checks + 1)); fails=$((fails + 1)); echo "  FAIL $1 — $2"; }
has()   { case "$3" in *"$2"*) ok ;; *) bad "$1" "missing [$2] in: $3" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "unexpected [$2] in: $3" ;; *) ok ;; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/data" "$T/clones"
# fake gh: answers from $FAKE_DIR/<repo>.<channel>.json, `[]` when the file is missing;
# FAKE_DOWN=1 makes every call fail (auth expired / network gone). Bash only — the temp dir
# never reaches a native process as data.
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ "${FAKE_DOWN:-0}" = 1 ] && exit 1
if [ "$1" = api ]; then
  [ "$2" = rate_limit ] && { echo '{}'; exit 0; }
  path="${2%%\?*}"; repo=$(printf '%s' "$path" | cut -d/ -f3)
  chan=$(printf '%s' "$path" | cut -d/ -f4-5 | tr '/' '-')
  f="$FAKE_DIR/$repo.$chan.json"
elif [ "$1" = pr ] && [ "$2" = list ]; then
  repo=""; state=""
  while [ $# -gt 0 ]; do
    case "$1" in --repo) repo="${2#*/}"; shift ;; --state) state="$2"; shift ;; esac; shift
  done
  f="$FAKE_DIR/$repo.$state.json"
else
  exit 2
fi
[ -f "$f" ] && cat "$f" || echo '[]'
EOF
chmod +x "$T/bin/gh"

D="$T/data"
printf '%s' '[
 {"created_at":"2025-12-31T00:00:00Z","user":{"login":"peer"},"html_url":"u0","body":"old, before the cursor"},
 {"created_at":"2026-01-02T00:00:00Z","user":{"login":"peer"},"html_url":"u1","body":"retest\non the merged PR"},
 {"created_at":"2026-01-03T00:00:00Z","user":{"login":"op"},"html_url":"u2","body":"from the other own machine"}]' > "$D/one.issues-comments.json"
printf '%s' '[{"created_at":"2026-01-02T01:00:00Z","user":{"login":"peer"},"html_url":"u3","body":"inline nit"}]' > "$D/one.pulls-comments.json"
printf '%s' '[{"number":7,"title":"new work","author":{"login":"peer"},"createdAt":"2026-01-02T02:00:00Z","headRefName":"peer-branch"},
              {"number":8,"title":"made here","author":{"login":"op"},"createdAt":"2026-01-02T03:00:00Z","headRefName":"local-branch"}]' > "$D/one.open.json"
printf '%s' '[{"number":5,"title":"our PR","mergedBy":{"login":"peer"},"mergedAt":"2026-01-02T04:00:00Z","headRefName":"x"}]' > "$D/one.merged.json"
printf '%s' '[{"created_at":"2026-01-01T12:00:00Z","user":{"login":"peer"},"html_url":"u9","body":"slow channel"}]' > "$D/two.issues-comments.json"

# a local clone of "one" carrying local-branch: PR #8 must be marked as made on this machine
git init -q "$T/clones/one"
git -C "$T/clones/one" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
git -C "$T/clones/one" branch local-branch

run() {  # run <tag> <repos> [extra env...]
  local tag="$1" repos="$2"; shift 2
  env PATH="$T/bin:$PATH" FAKE_DIR="$D" REPO_ACTIVITY_STATE_DIR="$T/state" REPO_ACTIVITY_TAG="$tag" \
      GH_WATCH_REPOS="$repos" COLLAB_WATCH_CLONE_ROOT="$T/clones" "$@" bash "$W" once 2>&1 | tr -d '\r'
}
seed() { mkdir -p "$T/state"; echo "2026-01-01T00:00:00Z" > "$T/state/repo-activity-$1-cursor.txt"; }

echo "round 1: every channel reports"
seed a; out=$(run a "acme/one")
has   "comment on a merged PR"        "COMMENT acme/one u1 [peer]" "$out"
has   "multi-line body flattened"     "retest on the merged PR" "$out"
has   "own-account comment reported"  "[op] 2026-01-03T00:00:00Z :: from the other own machine" "$out"
has   "inline review comment"         "COMMENT acme/one u3 [peer]" "$out"
has   "new PR"                        "PR acme/one #7: new work (peer)" "$out"
has   "merge judged by mergedBy"      "MERGED acme/one #5: our PR (merged by peer)" "$out"
has   "local branch marked"           "#8: made here (op) — branch is LOCAL" "$out"
hasnt "foreign branch not marked"     "#7: new work (peer) — branch is LOCAL" "$out"
hasnt "event before the cursor"       "u0" "$out"
cur=$(tr -d '\r\n' < "$T/state/repo-activity-a-cursor.txt")
[[ "$cur" == "2026-01-03T00:00:00Z" ]] && ok || bad "cursor advanced to the newest event" "got $cur"

echo "round 2: nothing repeats (GitHub's since is inclusive)"
out=$(run a "acme/one")
hasnt "newest comment not replayed" "u2" "$out"
hasnt "no PR replayed" "PR acme/one" "$out"

echo "negative control: an author filter on the own login swallows the other own machine"
seed b; out=$(run b "acme/one" GH_SELF_LOGIN=op)
hasnt "own-account comment gone under a self filter" "from the other own machine" "$out"
has   "peer still reported under the self filter" "u1 [peer]" "$out"

echo "include filter reports only the named login"
seed c; out=$(run c "acme/one" GH_ONLY_LOGINS=peer)
has   "named login reported" "u1 [peer]" "$out"
hasnt "other login dropped" "[op]" "$out"
has   "the price is announced" "NOT replayed" "$out"

echo "negative control: two watches sharing ONE cursor swallow the slower one's event"
seed d; run d "acme/one" >/dev/null           # advances cursor d to 2026-01-03
out=$(run d "acme/two")                       # its 2026-01-01T12 event is now "old"
hasnt "shared cursor swallowed the event (this is why tags must differ)" "slow channel" "$out"
seed e; out=$(run e "acme/two")
has   "own cursor reports it" "slow channel" "$out"

echo "gh unreachable: said loudly, cursor untouched"
seed f; out=$(run f "acme/one" FAKE_DOWN=1)
has "blind watch announces itself" "WATCH-ERROR: gh cannot reach GitHub" "$out"
cur=$(tr -d '\r\n' < "$T/state/repo-activity-f-cursor.txt")
[[ "$cur" == "2026-01-01T00:00:00Z" ]] && ok || bad "cursor unchanged while blind" "got $cur"

echo "lock: a live holder is respected"
seed g; echo $$ > "$T/state/repo-activity-g.pid"
out=$(run g "acme/one")
has   "duplicate watcher refused" "already armed" "$out"
hasnt "and it polled nothing" "COMMENT" "$out"

echo "arm script: TERM tears down the whole tree (a trap that does not exit swallows TERM)"
printf '%s\n' '{"repo_watches":[{"tag":"arm","repos":["acme/one"],"interval":30}]}' > "$T/arm.json"
env PATH="$T/bin:$PATH" FAKE_DIR="$D" COLLAB_WATCH_CONFIG="$T/arm.json" COLLAB_WATCH_STATE="$T/armstate" \
    COLLAB_WATCH_CLONE_ROOT="$T/clones" bash "$HERE/collab-watch.sh" > "$T/arm.out" 2>&1 &
A=$!
payload=""
for _ in $(seq 1 20); do
  payload=$(cat "$T/armstate/repo-activity-arm.pid" 2>/dev/null)
  [[ -n "$payload" ]] && break
  sleep 0.5
done
[[ -n "$payload" ]] && kill -0 "$payload" 2>/dev/null && ok || bad "arm script started the repo watch (control)" "$(cat "$T/arm.out")"
kill "$A" 2>/dev/null
gone=0
for _ in $(seq 1 24); do
  if ! kill -0 "$A" 2>/dev/null && { [[ -z "$payload" ]] || ! kill -0 "$payload" 2>/dev/null; }; then gone=1; break; fi
  sleep 0.5
done
if [[ $gone -eq 1 ]]; then ok; else
  bad "arm script and payload gone after TERM" "arm alive=$(kill -0 "$A" 2>/dev/null && echo yes || echo no), payload alive=$(kill -0 "$payload" 2>/dev/null && echo yes || echo no)"
  kill -9 "$A" "$payload" 2>/dev/null
fi
[[ ! -f "$T/armstate/repo-activity-arm.pid" ]] && ok || bad "payload released its lock on TERM" "lock still there"

echo
if [[ $fails -eq 0 ]]; then echo "test-repo-activity-watch: all $checks checks passed"; exit 0; fi
echo "test-repo-activity-watch: $fails of $checks checks FAILED"; exit 1
