#!/usr/bin/env bash
# session-pull.sh — SessionStart hook: bring the brain and its neighbour repos up to date
# before work starts, on every machine the brain runs on.
#
# Why: a brain that runs on several machines starts a session on a checkout another
# machine has moved on from — the rules, ledgers and suite fixes of yesterday's session
# are on the remote, not here. Pulling by hand is the step that gets forgotten.
#
# OPT-IN: runs only when the instance has config/session-pull.json (template:
# core/templates/session-pull.json). Without it: no output, nothing touched.
#
# What it pulls, in this order:
#   1. the brain itself;
#   2. every repo config/ecosystem.json records with a path (the same list
#      helpers/session-closing.sh and scripts/handover-gate.sh read — no second list);
#   3. the "extra" entries of config/session-pull.json — only for repos ecosystem.json does
#      not carry (the shared-memory repo is one: it is no suite and no pinned part of the
#      brain, so ecosystem-sync.py never records it).
# What it NEVER pulls: anything inside the brain (the core submodule follows the
# marketplace pin through scripts/brain-update.sh, never a plain pull) and any other
# submodule checkout. One move it does make: a clean detached core/ that lags the brain's own
# pin is checked out on it, forward only (step 1b, before and after the brain pull) — the pin is
# what brain-update.sh already committed on another machine, and new hooks next to an old core
# lock the session out.
#
# Per repo: uncommitted changes = reported, nothing touched (untracked files do not count —
# git itself refuses a fast-forward that would overwrite one) · detached HEAD or no upstream
# = skipped with a note · behind = `merge --ff-only` after a fetch · diverged = reported ·
# missing with a recorded remote = cloned. Nothing is ever stashed, reset or rebased.
#
# Hook-safe: all output on stderr, exit 0 always. No `timeout` (absent on macOS): every
# network call runs under a stall limit of its own (background job + kill, plus git's
# low-speed limit and a non-interactive ssh), and the whole run under a budget — a dead
# network costs at most the budget, never a blocked start.
#
# Per machine: `- Session pull: off` in config/machines/<key>.md switches it off there
# (a show machine that must not change on a show day). Key: scripts/machine-key.sh.
#
# Hooks of one event run in parallel, so the memory import of the same start may read the
# snapshot from before the pull; when the pull changed docs/memory-snapshot/ it says so.
set -u
R="${CLAUDE_PROJECT_DIR:-$PWD}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CFG="$R/config/session-pull.json"
log() { printf '[session-pull] %s\n' "$*" >&2; }
[ -f "$CFG" ] || exit 0
command -v git >/dev/null 2>&1 || { log "git not found — nothing pulled"; exit 0; }

# Per-machine opt-out (identity data in the machine profile).
if [ -f "$HERE/../scripts/machine-key.sh" ]; then
  # shellcheck source=../scripts/machine-key.sh
  . "$HERE/../scripts/machine-key.sh"
  key=$(machine_key)
  prof="$R/config/machines/$key.md"
  if [ -n "$key" ] && [ -f "$prof" ]; then
    sp=$(sed -n 's/^- Session pull:[[:space:]]*//p' "$prof" | head -1 | tr -d '\r' | tr '[:upper:]' '[:lower:]')
    case "$sp" in off*) log "off on this machine (config/machines/$key.md) — nothing pulled"; exit 0 ;; esac
  fi
fi

command -v node >/dev/null 2>&1 || { log "node not found — config/session-pull.json not readable, nothing pulled"; exit 0; }
# The plan, one record per line, fields split by the unit separator (0x1f): a tab would
# collapse an empty field (IFS treats whitespace runs as one separator).
plan=$(node -e '
const fs = require("fs");
const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const num = (v, d) => (Number.isInteger(v) && v > 0 ? v : d);
const S = "\x1f", clean = (s) => String(s == null ? "" : s).replace(/[\x1f\r\n]/g, " ");
console.log(["cfg", num(c.stall_seconds, 15), num(c.budget_seconds, 45)].join(S));
const out = (n, p, r) => console.log(["repo", clean(n), clean(p), clean(r)].join(S));
if (c.ecosystem !== false) {
  let e = null;
  try { e = JSON.parse(fs.readFileSync(process.argv[2], "utf8")); } catch (_) {}
  for (const [n, v] of Object.entries((e && e.repos) || {})) if (v && v.path) out(n, v.path, v.remote);
}
for (const x of Array.isArray(c.extra) ? c.extra : [])
  if (x && x.path) out(x.name || String(x.path).replace(/[\\/]+$/, "").split(/[\\/]/).pop(), x.path, x.remote);
' "$CFG" "$R/config/ecosystem.json" 2>/dev/null) || { log "config/session-pull.json unreadable (invalid JSON?) — nothing pulled"; exit 0; }
plan=$(printf '%s\n' "$plan" | tr -d '\r')
US=$(printf '\037')
IFS="$US" read -r _ STALL BUDGET <<< "$plan"
case "$STALL" in ''|*[!0-9]*) STALL=15 ;; esac
case "$BUDGET" in ''|*[!0-9]*) BUDGET=45 ;; esac

TMPF=$(mktemp 2>/dev/null) || TMPF="${TMPDIR:-/tmp}/session-pull.$$"
trap 'rm -f "$TMPF"' EXIT
export GIT_TERMINAL_PROMPT=0 GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME="$STALL"

# <seconds> <outfile> cmd... — runs cmd with a stall limit; 124 when it had to be killed.
run_limited() {
  local s=$1 out=$2 pid n=0
  shift 2
  "$@" >"$out" 2>&1 </dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$n" -ge $((s * 5)) ]; then
      kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 0.2
    n=$((n + 1))
  done
  wait "$pid"
}

# A non-interactive ssh with a connect limit — unless the operator configured ssh for git
# (env or core.sshCommand): then theirs stays, the stall limit still holds.
ssh_cmd_for() {
  [ -n "${GIT_SSH_COMMAND:-}${GIT_SSH:-}" ] && return 0
  if [ -n "$1" ]; then
    git -C "$1" config --get core.sshCommand >/dev/null 2>&1 && return 0
  else
    git config --get core.sshCommand >/dev/null 2>&1 && return 0
  fi
  printf 'ssh -o BatchMode=yes -o ConnectTimeout=%s' "$STALL"
}

# <seconds> <repo-dir or ''> git-args...
net() {
  local s=$1 d=$2 sc
  shift 2
  sc=$(ssh_cmd_for "$d")
  if [ -n "$sc" ]; then
    run_limited "$s" "$TMPF" env GIT_SSH_COMMAND="$sc" git "$@"
  else
    run_limited "$s" "$TMPF" git "$@"
  fi
}

why() { if [ "$1" -eq 124 ]; then printf 'no answer within %ss' "$2"; else tail -1 "$TMPF" 2>/dev/null; fi; }

n_checked=0; n_updated=0; n_cloned=0; n_look=0; n_late=0
BEFORE=""; AFTER=""
LOOKS=""
# A finding that needs someone: logged like everything else AND kept for the stdout summary
# at the end — SessionStart stderr does not reach the session's context, so a dirty or
# diverged repo reported only there would be invisible (success reports itself, failure
# needs a channel).
look() { log "$*"; LOOKS="$LOOKS  - $*"$'\n'; n_look=$((n_look + 1)); }

# <label> <dir> — the per-repo rules from the header.
pull_one() {
  local name=$1 p=$2 br rem ahead behind rc dirty
  BEFORE=""; AFTER=""
  n_checked=$((n_checked + 1))
  dirty=$(git -C "$p" status --porcelain --untracked-files=no 2>/dev/null)
  if [ -n "$dirty" ]; then
    # the brain whose only change is core/ off its pin: that is the cause, not local edits
    if [ "$name" = brain ] && [ "$(printf '%s\n' "$dirty" | awk '{print $NF}')" = core ]; then
      look "$name: only core/ is off the brain's pin (see the core line) — not pulled, nothing touched"; return
    fi
    look "$name: uncommitted changes — not pulled, nothing touched"; return
  fi
  br=$(git -C "$p" symbolic-ref -q --short HEAD 2>/dev/null) || { log "$name: detached HEAD — skipped"; return; }
  rem=$(git -C "$p" config --get "branch.$br.remote" 2>/dev/null)
  if [ -z "$rem" ] || ! git -C "$p" config --get "branch.$br.merge" >/dev/null 2>&1; then
    log "$name: no upstream on '$br' — skipped"; return
  fi
  net "$STALL" "$p" -C "$p" fetch -q "$rem"; rc=$?
  if [ "$rc" -ne 0 ]; then
    look "$name: fetch failed — $(why "$rc" "$STALL")"; return
  fi
  read -r ahead behind <<< "$(git -C "$p" rev-list --left-right --count 'HEAD...@{u}' 2>/dev/null)"
  case "$ahead$behind" in ''|*[!0-9]*) log "$name: upstream of '$br' not readable — skipped"; return ;; esac
  [ "$behind" -eq 0 ] && return
  if [ "$ahead" -ne 0 ]; then
    look "$name ($br): diverged — $ahead local and $behind upstream commits, not pulled"; return
  fi
  BEFORE=$(git -C "$p" rev-parse HEAD)
  if git -C "$p" -c submodule.recurse=false merge -q --ff-only '@{u}' >"$TMPF" 2>&1; then
    AFTER=$(git -C "$p" rev-parse HEAD)
    log "$name ($br): updated ${BEFORE:0:7}..${AFTER:0:7} ($behind commit(s))"; n_updated=$((n_updated + 1))
  else
    look "$name ($br): fast-forward refused — $(tail -1 "$TMPF")"; BEFORE=""
  fi
}

# 1b. core/ follows the brain's pin. Measured 2026-10-22 on a machine a week behind: the pull
# brought hooks that call core files the old checkout did not have, every tool call was refused
# from then on, and the session could not repair itself. The pin another machine committed (via
# brain-update.sh) is the released state, so this is no plain pull. It goes by STATE, at every
# start, before and after the brain pull (review of #78): a move that failed once, or a machine
# stuck before this existed, heals at the next start instead of blocking the brain pull for good.
# Moved only FORWARD, only a clean detached core/ that sits on a commit an earlier brain commit
# pinned, never a declared alpha; everything else stays and is named. A backwards pin is never
# checked out: that is the downgrade brain-update.sh refuses as well.
core_alpha() {   # the alpha the brain declares for core/ (.claude/rules/local-machinery.json, until today or later)
  node -e '
let a = {};
try { a = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).alpha || {}; } catch (_) {}
const today = new Date().toISOString().slice(0, 10);
for (const [k, v] of Object.entries(a))
  if ((k === "core" || k.startsWith("core/")) && v && typeof v === "object" && String(v.until || "") >= today) { console.log(k); break; }
' "$R/.claude/rules/local-machinery.json" 2>/dev/null
}
align_core() {
  local pin at c was="" left i
  [ -e "$R/core/.git" ] || return 0
  pin=$(git -C "$R" rev-parse -q --verify "HEAD:core" 2>/dev/null) || return 0
  at=$(git -C "$R/core" rev-parse -q --verify HEAD 2>/dev/null) || return 0
  [ "$at" = "$pin" ] && return 0
  if [ -n "$(core_alpha)" ]; then log "core: a declared alpha on ${at:0:7} (the brain pins ${pin:0:7}) — left"; return 0; fi
  if git -C "$R/core" symbolic-ref -q HEAD >/dev/null 2>&1 || ! git -C "$R/core" diff --quiet HEAD -- 2>/dev/null; then
    look "core: on a branch or with local edits (${at:0:7}), the brain pins ${pin:0:7} — left; run: bash core/scripts/brain-update.sh"; return 0
  fi
  if ! git -C "$R/core" cat-file -e "$pin^{commit}" 2>/dev/null; then
    net $((STALL * 2)) "$R/core" -C "$R/core" fetch -q --tags origin; rc=$?
    [ "$rc" -eq 0 ] || { look "core: the brain's pin ${pin:0:7} is not here and the fetch failed — $(why "$rc" $((STALL * 2)))"; return 0; }
  fi
  if git -C "$R/core" merge-base --is-ancestor "$pin" "$at" 2>/dev/null; then
    look "core: the brain pins an OLDER core (${at:0:7} -> ${pin:0:7}) — not checked out; an intended rollback: git -C core checkout --detach $pin"
    return 0
  fi
  if ! git -C "$R/core" merge-base --is-ancestor "$at" "$pin" 2>/dev/null; then
    look "core: ${at:0:7} is not behind the brain's pin ${pin:0:7} — left; run: bash core/scripts/brain-update.sh"; return 0
  fi
  for c in $(git -C "$R" log --format=%H -n 500 -- core 2>/dev/null); do
    [ "$(git -C "$R" rev-parse -q --verify "$c:core" 2>/dev/null)" = "$at" ] && { was=$c; break; }
  done
  [ -n "$was" ] || { look "core: ${at:0:7} is no pin this brain ever committed — left; run: bash core/scripts/brain-update.sh"; return 0; }
  if ! git -C "$R/core" checkout -q --detach "$pin" >"$TMPF" 2>&1; then
    look "core: could not move to the pin ${pin:0:7} — $(tail -1 "$TMPF"); run: bash core/scripts/brain-update.sh"; return 0
  fi
  # Windows: a file another process holds open is not replaced and git still exits 0 (measured 2026-10-24, Git for
  # Windows: a Python or Node handle on a core file - "unable to unlink", rc 0, the old content left; a running bash
  # script is replaced fine). core/ was clean before the move, so what differs now is that: tried again a few times.
  left=$(git -C "$R/core" status --porcelain --untracked-files=no 2>/dev/null); i=0
  while [ -n "$left" ] && [ "$i" -lt 5 ]; do
    sleep 1; i=$((i + 1))
    git -C "$R/core" checkout -q -- . >/dev/null 2>&1
    left=$(git -C "$R/core" status --porcelain --untracked-files=no 2>/dev/null)
  done
  if [ -n "$left" ]; then
    look "core: on the pin ${pin:0:7}, but $(printf '%s\n' "$left" | wc -l | tr -d ' ') file(s) kept their old content (held open by another process) — after this start: git -C core checkout -- ."
  else
    log "core: ${at:0:7} -> ${pin:0:7} (the brain's pin)"
  fi
}

# 1. the brain
self=$(cd "$R" 2>/dev/null && pwd -P)
if [ -e "$R/.git" ]; then
  align_core      # a core/ that lags the pin heals first - else the brain shows ' M core' and is never pulled
  pull_one brain "$R"
  if [ -n "$AFTER" ] && [ -n "$(git -C "$R" diff --name-only "$BEFORE" "$AFTER" -- docs/memory-snapshot 2>/dev/null)" ]; then
    log "brain: the pull changed docs/memory-snapshot — the memory import of this start may have read the old one; re-run: node core/helpers/memory-sync.cjs import"
  fi
  [ -n "$AFTER" ] && align_core   # the pin the pull brought
fi

# 2 + 3. neighbour repos
seen=$'\n'
while IFS="$US" read -r kind name p remote; do
  [ "$kind" = "repo" ] || continue
  case "$p" in "~"|"~/"*) p="$HOME${p#\~}" ;; esac
  case "$p/" in "$R/"*|"$self/"*) continue ;; esac     # the brain and what is mounted in it
  if [ -d "$p" ]; then
    real=$(cd "$p" 2>/dev/null && pwd -P)
    case "$real/" in "$self/"*) continue ;; esac
  fi
  case "$seen" in *$'\n'"$p"$'\n'*) continue ;; esac
  seen="$seen$p"$'\n'
  if [ "$SECONDS" -ge "$BUDGET" ]; then n_late=$((n_late + 1)); continue; fi
  if [ ! -e "$p" ] || { [ -d "$p" ] && [ -z "$(ls -A "$p" 2>/dev/null)" ]; }; then
    if [ -z "$remote" ]; then log "$name: not checked out at $p and no remote recorded — skipped"; continue; fi
    mkdir -p "$(dirname "$p")" 2>/dev/null
    net $((STALL * 4)) "" clone -q "$remote" "$p"; rc=$?
    if [ "$rc" -eq 0 ]; then
      log "$name: cloned from $remote (was missing)"; n_cloned=$((n_cloned + 1))
    else
      look "$name: clone from $remote failed — $(why "$rc" $((STALL * 4)))"
    fi
    continue
  fi
  if [ ! -e "$p/.git" ]; then log "$name: $p is not a git checkout — skipped"; continue; fi
  if [ -n "$(git -C "$p" rev-parse --show-superproject-working-tree 2>/dev/null)" ]; then
    log "$name: a submodule — follows its superproject's pin, not pulled"; continue
  fi
  pull_one "$name" "$p"
done <<< "$plan"

late=""
[ "$n_late" -gt 0 ] && late=", $n_late not reached (budget ${BUDGET}s spent)"
log "done in ${SECONDS}s: $n_checked checked, $n_updated updated, $n_cloned cloned, $n_look need a look$late"
# stdout reaches the session: only what needs a look, never the all-clear (silence = fine).
if [ "$n_look" -gt 0 ] || [ "$n_late" -gt 0 ]; then
  printf 'session-pull: %s repo(s) need a look%s\n%s' "$n_look" "$late" "$LOOKS"
fi
exit 0
