# preflight.ps1 (PowerShell edition) — checks onboarding prerequisites, reports,
# installs NOTHING. The authoritative edition is preflight.sh (Git Bash); this one
# exists for the view from PowerShell and checks the same items.
#
# ENCODING: this file MUST keep its UTF-8 BOM. Windows PowerShell 5.1 reads a
# BOM-less .ps1 as ANSI; the em-dash bytes (E2 80 94) then decode to CP1252, whose
# third byte 0x94 is a smart quote that PS 5.1 accepts as a string terminator —
# strings close mid-sentence and the whole file fails to parse (measured 2026-08-14,
# Win 11 / PS 5.1: ParserError, zero checks ran).
$fail = 0
function OK($m)  { Write-Host "  OK   $m" }
function BAD($m, $fix) { Write-Host "  FAIL $m"; Write-Host "     -> $fix"; $script:fail = 1 }
# WARN = noteworthy, but no reason to stop the onboarding (does NOT set fail).
function WARN($m, $fix) { Write-Host "  WARN $m"; Write-Host "     -> $fix" }

Write-Host "=== Onboarding preflight (PowerShell) ==="

if (Get-Command node -ErrorAction SilentlyContinue) {
  $v = (node --version).TrimStart('v')
  $parts = $v.Split('.'); $major = [int]$parts[0]; $minor = [int]$parts[1]
  if ($major -gt 23 -or ($major -eq 23 -and $minor -ge 6)) { OK "node $v (>= 23.6)" }
  else { BAD "node $v too old" "install Node >= 23.6 (nodejs.org)" }
} else { BAD "node missing" "winget install OpenJS.NodeJS" }

if (Get-Command git -ErrorAction SilentlyContinue) {
  OK "git present"
  # git ignores the Windows setting LongPathsEnabled and brings core.longpaths of its
  # own. Without the switch, a clone of a deep repo aborts mid-run (measured
  # 2026-08-10: 193-character target path -> "Filename too long", despite
  # LongPathsEnabled=1 in the registry).
  $lp = git config --get core.longpaths 2>$null
  if ($lp -eq 'true') { OK "git core.longpaths active (long paths)" }
  else { BAD "git core.longpaths off" "git config --global core.longpaths true — the Windows setting 'LongPathsEnabled' alone is NOT enough, git has its own switch" }
} else { BAD "git missing" "winget install Git.Git" }

# Execute Python instead of merely finding it: the Microsoft Store stub (python3.exe)
# sits in PATH but only opens the Store. The core scripts need Python 3.9 or newer,
# stdlib only (docs/os-traps.md OS-13 — same floor as preflight.sh).
$py = $null
foreach ($c in @('python3', 'python')) {
  if (Get-Command $c -ErrorAction SilentlyContinue) {
    & $c -c 'import sys' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $py = $c; break }
  }
}
if (-not $py) { BAD "python missing (or only the Microsoft Store stub)" "install Python 3.9 or newer (python.org, tick 'Add python.exe to PATH') — then open a NEW terminal" }
else {
  $pyv = & $py -c 'import platform; print(platform.python_version())'
  & $py -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { OK "python: $py $pyv (>= 3.9)" }
  else { BAD "python: $py $pyv too old" "install Python 3.9 or newer (python.org) — the core scripts need 3.9+" }
}

if (Get-Command gh -ErrorAction SilentlyContinue) {
  gh auth status *> $null
  if ($LASTEXITCODE -eq 0) { OK "gh CLI logged in" } else { BAD "gh not logged in" "gh auth login" }
} else { BAD "gh CLI missing" "winget install GitHub.cli — then open a NEW terminal, otherwise gh stays missing from PATH" }

# The question is "can I reach GitHub over SSH", not "is an agent running" — same
# rationale as preflight.sh. ssh -T ALWAYS exits 1 (GitHub gives no shell), so the
# OUTPUT decides, never the exit code. StrictHostKeyChecking=accept-new keeps the
# first contact (no known_hosts entry yet) from failing with a perfect key.
$sshOut = (ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -T git@github.com 2>&1 | Out-String)
if ($sshOut -match 'successfully authenticated') {
  $who = ''; if ($sshOut -match 'Hi ([^!]+)!') { $who = " (as $($Matches[1]))" }
  OK "SSH access to GitHub proven$who"
  $agent = Get-Service ssh-agent -ErrorAction SilentlyContinue
  if ($agent -and $agent.Status -eq 'Running') { OK "ssh-agent service running" }
  else { WARN "ssh-agent service not running — harmless, access is already proven" "Only needed if your key has a passphrase. As ADMINISTRATOR (without admin rights: 'Access is denied'): Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent — then ssh-add" }
} else {
  # Missing SSH is only fatal when HTTPS does not reach GitHub either (same as preflight.sh).
  # @(...): a one-line SSH message leaves the pipeline as a STRING, and [0] on a string is
  # its first character (measured on Windows PowerShell 5.1) — docs/os-traps.md OS-12.
  $first = @($sshOut -split "`r?`n" | Where-Object { $_ })[0]
  $sshFix = "Create a key: ssh-keygen -t ed25519 · show the public key: type $env:USERPROFILE\.ssh\id_ed25519.pub · add it at https://github.com/settings/ssh/new · then run this script again"
  $httpsUrl = if ($env:PREFLIGHT_HTTPS_URL) { $env:PREFLIGHT_HTTPS_URL } else { 'https://github.com/arche-goah/agent-brain.git' }
  $env:GIT_TERMINAL_PROMPT = '0'; $env:GIT_HTTP_LOW_SPEED_LIMIT = '1'; $env:GIT_HTTP_LOW_SPEED_TIME = '10'
  git ls-remote $httpsUrl HEAD *> $null
  if ($LASTEXITCODE -eq 0) { WARN "SSH to GitHub not proven, but HTTPS works (ls-remote $httpsUrl)" "Clones and fetches over HTTPS are fine. Set up SSH if a plugin install or marketplace refresh fails: $sshFix" }
  else { BAD "GitHub not reachable — neither SSH (message: $first) nor HTTPS ($httpsUrl)" "Check the network first; then $sshFix" }
}

if (Get-Command claude -ErrorAction SilentlyContinue) { OK "claude CLI present" } else { BAD "claude CLI missing" "install Claude Code" }

Write-Host ""
if ($fail -eq 0) { Write-Host "Preflight: ALL GREEN" } else { Write-Host "Preflight: RED — work through the items, then measure again" }
exit $fail
