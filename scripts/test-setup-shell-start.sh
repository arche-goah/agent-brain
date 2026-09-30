#!/usr/bin/env bash
# covers: setup-shell-start
# test-setup-shell-start.sh — the Windows branch of setup-shell-start.sh must not end
# silently when a PowerShell query fails.
#
# WHY (measured 2026-09-30, third Windows machine of one brain): started from a
# PowerShell 7 parent, powershell.exe inherits pwsh's PSModulePath, cannot load
# Microsoft.PowerShell.Security, and Get-ExecutionPolicy fails. Under set -euo pipefail
# that one failing query ended the script: the Windows PowerShell profile was written,
# the pwsh profile was not, the measurement line was missing, and nothing said so.
#
# The fixture runs on every OS: fake `uname` (MINGW), `powershell.exe` and `pwsh` on
# PATH, a throwaway HOME and a throwaway brain. The fakes behave like the measured
# machine: $PROFILE always answers, the ExecutionPolicy cmdlets fail while PSModulePath
# is set (they live in Microsoft.PowerShell.Security, the module that did not load).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/setup-shell-start.sh"
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

[ -f "$SCRIPT" ] || { bad "setup-shell-start.sh not found"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home" "$TMP/brain" "$TMP/prof"
printf 'x\n' > "$TMP/brain/CLAUDE.md"

printf '#!/usr/bin/env bash\necho MINGW64_NT-10.0\n' > "$TMP/bin/uname"
for exe in powershell.exe pwsh; do
  cat > "$TMP/bin/$exe" <<EOF
#!/usr/bin/env bash
cmd="\$*"
case "\$cmd" in *ExecutionPolicy*)
  if [ -n "\${PSModulePath:-}" ]; then echo "CouldNotAutoloadMatchingModule" >&2; exit 1; fi ;;
esac
case "\$cmd" in
  *PROFILE*)             echo "$TMP/prof/$exe/profile.ps1" ;;
  *Get-ExecutionPolicy*) [ -n "\${FAKE_POLICY_FAILS:-}" ] && exit 1; echo RemoteSigned ;;
  *) exit 0 ;;
esac
EOF
done
chmod +x "$TMP/bin/"*

run() { # extra env assignments as arguments
  env "$@" HOME="$TMP/home" PATH="$TMP/bin:$PATH" bash "$SCRIPT" "$TMP/brain" 2>&1
}

# ── 1. an inherited PSModulePath does not end the script ───────────────────
out="$(run PSModulePath='C:\Program Files\PowerShell\7\Modules')"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 with an inherited PSModulePath" || bad "exit $rc with an inherited PSModulePath: $out"
for exe in powershell.exe pwsh; do
  if grep -q "brain shell-start" "$TMP/prof/$exe/profile.ps1" 2>/dev/null; then
    ok "$exe profile written"
  else
    bad "$exe profile NOT written"
  fi
done
case "$out" in
  *Measurement*) ok "measurement line reached" ;;
  *)             bad "measurement line missing: $out" ;;
esac

# ── 2. a policy query that fails anyway is reported, not swallowed ─────────
rm -rf "$TMP/prof" "$TMP/home"; mkdir -p "$TMP/prof" "$TMP/home"
out="$(run FAKE_POLICY_FAILS=1)"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 when Get-ExecutionPolicy fails" || bad "exit $rc when Get-ExecutionPolicy fails: $out"
case "$out" in
  *"WARN ExecutionPolicy of pwsh could not be read"*) ok "failed policy query is named" ;;
  *) bad "failed policy query not reported: $out" ;;
esac
grep -q "brain shell-start" "$TMP/prof/pwsh/profile.ps1" 2>/dev/null \
  && ok "pwsh profile still written" || bad "pwsh profile NOT written after a failed policy query"

[ "$fail" -eq 0 ] && echo "test-setup-shell-start: all checks passed"
exit "$fail"
