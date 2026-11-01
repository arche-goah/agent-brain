#!/usr/bin/env bash
# Fixture for scripts/eco_owner.py — the ONE owner whose PRs, code-scanning alerts and
# shared-memory repo a session start asks GitHub about — and for its wiring in
# helpers/session-bootup.sh.
# Incident 2026-10-21: the template marketplace "your-org" is a real GitHub organisation; a
# freshly bootstrapped brain listed 41 PRs of strangers as its own work. A placeholder is never
# an owner and never falls through to the next marketplace (a vendor's is no owner either).
# Fresh-brain trial 2026-10-31: the first marketplace ALONE decided, so a stranger whose settings
# named someone else's marketplace queried that organisation's PRs and repos at every start; a
# stranger with only the placeholder had no owner and a red line no action cleared. Now:
# "owner" in config/ecosystem.json, else a marketplace the login can really see, else the login.
# The real script runs; gh is a recorder that replaces subprocess.run inside the same Python
# process (no network, every call logged). A stub binary on PATH would not do: Windows'
# CreateProcess never finds a script named `gh`, and Python never starts bash (OS-14).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOT="$HERE/../helpers/session-bootup.sh"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1 — got '$2'"; fails=$((fails+1)); }
is() { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$2"; }

# OS-3: every path reaches python as data (argument, env), so it is stated natively.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(native "$(mktemp -d)")"; trap 'rm -rf "$T"' EXIT
ECO="$(native "$HERE/eco_owner.py")"
[ -f "$ECO" ] || { echo "test-eco-owner: scripts/eco_owner.py missing"; exit 1; }

# What gh answers (FAKE_GH): "missing" (not installed), "offline" (no data at all), or
# "<login>;<repo>" where <repo> is none (the login cannot see it) or <visibility>:<permission>.
FAKE='import json, os, runpy, subprocess, sys
spec, log = os.environ.get("FAKE_GH", ""), os.environ["FAKE_GH_LOG"]
class R:
    def __init__(self, rc, out): self.returncode, self.stdout, self.stderr = rc, out, ""
def run(a, **k):
    if not a or a[0] != "gh": raise AssertionError("unexpected command %r" % (a,))
    with open(log, "a", encoding="utf-8", newline="\n") as f:  # OS-2: LF on every platform
        f.write(" ".join(x for x in a[1:] if x != "-f" and not x.startswith("query=")) + "\n")
    if spec == "missing": raise FileNotFoundError("gh")
    if spec == "offline": return R(1, "")
    login, _, repo = spec.partition(";")
    data = {"viewer": {"login": login}}
    if any(x.startswith("o=") for x in a):
        if repo == "none":
            return R(1, json.dumps({"data": dict(data, repository=None), "errors": [{"type": "NOT_FOUND"}]}))
        vis, perm = repo.split(":")
        data["repository"] = {"isPrivate": vis == "private", "viewerPermission": perm}
    return R(0, json.dumps({"data": data}))
subprocess.run = run
sys.argv = ["eco_owner.py"] + sys.argv[1:]
runpy.run_path(os.environ["ECO"], run_name="__main__")
'
mk() { # $1 = file, rest = repo values, in order
  local f="$1"; shift; local body="" i=0
  for r in "$@"; do i=$((i+1)); body="$body${body:+,}\"m$i\":{\"source\":{\"source\":\"github\",\"repo\":\"$r\"}}"; done
  printf '{"extraKnownMarketplaces":{%s}}' "$body" > "$f"
}
brain() { # $1 = project marketplaces (space-separated owner/name), $2 = user ones, $3 = ecosystem "owner"
  local pr ur
  read -ra pr <<< "${1:-}"; read -ra ur <<< "${2:-}"
  rm -rf "$T/p" "$T/cfg"; mkdir -p "$T/p/.claude" "$T/p/config" "$T/cfg"
  [ "${#pr[@]}" -gt 0 ] && mk "$T/p/.claude/settings.json" "${pr[@]}"
  [ "${#ur[@]}" -gt 0 ] && mk "$T/cfg/settings.json" "${ur[@]}"
  [ -n "${3:-}" ] && printf '{"owner": "%s", "repos": {}}\n' "$3" > "$T/p/config/ecosystem.json"
  : > "$T/gh.log"
}
owner() { # $1 = what gh answers, [$2 = session id] -> the owner eco_owner.py prints
  local hi='{}'; [ -n "${2:-}" ] && hi="{\"session_id\":\"$2\"}"
  CLAUDE_CONFIG_DIR="$T/cfg" FAKE_GH="$1" FAKE_GH_LOG="$T/gh.log" ECO="$ECO" \
    "$PY" -c "$FAKE" --root "$T/p" --hook-input "$hi"
}
calls() { tr '\n' '|' < "$T/gh.log" | sed 's/|$//'; }

echo "1. the brain's own word: \"owner\" in config/ecosystem.json"
brain team-org/claude-marketplace "" my-org
is "explicit owner wins over a visible marketplace and the login" "$(owner 'me;private:READ')" my-org
is "explicit owner: GitHub is not asked at all"                   "$(calls)" ""
brain "" "" '<your-org>'
is "placeholder <your-org> as owner: ignored, the login instead"  "$(owner 'me')" me
brain "" "" your-org
is "placeholder your-org as owner: ignored, the login instead"    "$(owner 'me')" me

echo "2. the marketplace's org — only one the login can see and call its own"
brain team-org/claude-marketplace
is "private marketplace the login can read: its org"              "$(owner 'me;private:READ')" team-org
is "one call, about that repo"                                    "$(calls)" "api graphql o=team-org n=claude-marketplace"
brain team-org/claude-marketplace
is "public marketplace the login may write to: its org"           "$(owner 'me;public:WRITE')" team-org
brain other-org/claude-marketplace
is "marketplace the login cannot see (the trial): the login"      "$(owner 'stranger;none')" stranger
brain some-vendor/claude-marketplace
is "public marketplace the login only reads: the login"           "$(owner 'stranger;public:READ')" stranger
brain "" user-org/claude-marketplace
is "user-level marketplace when the project has none"             "$(owner 'me;private:READ')" user-org
brain proj-org/a user-org/b
is "project before user (control)"                                "$(owner 'me;private:ADMIN')" proj-org

echo "3. a template placeholder is no marketplace: the login, and GitHub is not asked about it"
brain your-org/claude-marketplace
is "your-org: the login"                                          "$(owner 'me;private:READ')" me
is "your-org: no question about that repo"                        "$(calls)" "api graphql"
brain Your-Org/claude-marketplace
is "case does not matter (Your-Org)"                              "$(owner 'me;private:READ')" me
brain '<your-org>/claude-marketplace'
is "<placeholder>: the login"                                     "$(owner 'me;private:READ')" me
brain "your-org/a some-vendor/b"
is "placeholder first: no fall-through to the next"               "$(owner 'me;private:READ')" me
is "  ... and the next is not asked about either"                 "$(calls)" "api graphql"
brain your-org/a some-vendor/b
is "placeholder in project: no fall-through to user"              "$(owner 'me;private:READ')" me
brain your-org-studio/claude-marketplace
is "a name that only contains it stays an owner"                  "$(owner 'me;private:READ')" your-org-studio

echo "4. gh gives no answer"
brain ""
is "no gh, nothing configured: no owner"                          "$(owner missing)" ""
brain your-org/claude-marketplace
is "no gh, placeholder marketplace: no owner"                     "$(owner missing)" ""
brain team-org/claude-marketplace
is "offline, never answered before: no owner"                     "$(owner offline)" ""
is "an answer is stored (control)"                                "$(owner 'me;private:READ' s1)" team-org
is "offline later: the last answer for that marketplace stands"   "$(owner offline s2)" team-org
mk "$T/p/.claude/settings.json" other-org/claude-marketplace
is "  ... but never for another marketplace"                      "$(owner offline s3)" ""

echo "5. one answer per session"
brain team-org/claude-marketplace
owner 'me;private:READ' s1 >/dev/null; : > "$T/gh.log"
is "same session (resume, compaction): the answer stands"         "$(owner 'me;public:READ' s1)" team-org
is "  ... without a call"                                         "$(calls)" ""
is "a new session asks again"                                     "$(owner 'me;public:READ' s2)" me

echo "6. the session start takes every owner from it"
is "one assignment of eco_owner, and it runs eco_owner.py" \
   "$(grep -c '^ *eco_owner=' "$BOOT")/$(grep -c '^eco_owner=$("$PY" "$HERE/../scripts/eco_owner.py" ' "$BOOT")" "1/1"

# The update check (the `upd=` heredoc) tests the same placeholder on its own (review of #73, round 3): an old-template
# brain must not ask GitHub about the placeholder marketplace at every start. Cut out AS SHIPPED; subprocess.run is
# replaced by a recorder as above.
UPDS="$(sed -n "/^upd=\$(BOOT_CORE_ALPHA=/,/^PY\$/p" "$BOOT" | sed '1d;$d')"
if [ -z "$UPDS" ] || ! printf '%s' "$UPDS" | "$PY" -c 'import sys; compile(sys.stdin.read(), "upd", "exec")' 2>/dev/null; then
  echo "test-eco-owner: update-check heredoc not found or broken in session-bootup.sh"; exit 1
fi
# The recorder goes in front of the snippet, both run as one program (the snippet's own `import subprocess` finds the
# module already patched); its sys.exit() ends the run as at a session start.
REC='import subprocess
class R: returncode, stdout = 1, ""
def run(a, **k):
    print("ask " + a[2].split("/contents/")[0][len("repos/"):]); return R()
subprocess.run = run
'
asks() { # $1 = project repos -> "ask <repo>" when the update check would call GitHub, else nothing
  local pr
  read -ra pr <<< "$1"
  rm -rf "$T/p" "$T/cfg"; mkdir -p "$T/p/.claude" "$T/cfg"
  mk "$T/p/.claude/settings.json" "${pr[@]}"
  (cd "$T/p" && CLAUDE_CONFIG_DIR="$T/cfg" "$PY" -c "$REC$UPDS")
}
echo "7. update check: asks GitHub only about a real marketplace"
is "real owner: one call (control)"                  "$(asks some-team/claude-marketplace)" "ask some-team/claude-marketplace"
is "template placeholder your-org: no call"          "$(asks your-org/claude-marketplace)" ""
is "case does not matter (Your-Org): no call"        "$(asks Your-Org/claude-marketplace)" ""
is "<placeholder>: no call"                          "$(asks '<your-org>/claude-marketplace')" ""

echo
if [ "$fails" -eq 0 ]; then echo "test-eco-owner: all checks passed"; exit 0; fi
echo "test-eco-owner: $fails check(s) FAILED"; exit 1
