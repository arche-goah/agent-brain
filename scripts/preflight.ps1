# preflight.ps1 (PowerShell edition) — checks onboarding prerequisites, reports,
# installs NOTHING. The authoritative edition is preflight.sh (Git Bash); this one
# exists for the view from PowerShell and checks the same items.
$fail = 0
function OK($m)  { Write-Host "  OK   $m" }
function BAD($m, $fix) { Write-Host "  FAIL $m"; Write-Host "     -> $fix"; $script:fail = 1 }

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
# sits in PATH but only opens the Store. The verify step needs a real Python
# (stdlib is enough).
$py = $null
foreach ($c in @('python3', 'python')) {
  if (Get-Command $c -ErrorAction SilentlyContinue) {
    & $c -c 'import sys' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $py = $c; break }
  }
}
if ($py) { OK "python: $py $(& $py -c 'import platform; print(platform.python_version())')" }
else { BAD "python missing (or only the Microsoft Store stub)" "install Python 3 (python.org, tick 'Add python.exe to PATH') — then open a NEW terminal" }

if (Get-Command gh -ErrorAction SilentlyContinue) {
  gh auth status *> $null
  if ($LASTEXITCODE -eq 0) { OK "gh CLI logged in" } else { BAD "gh not logged in" "gh auth login" }
} else { BAD "gh CLI missing" "winget install GitHub.cli — then open a NEW terminal, otherwise gh stays missing from PATH" }

$agent = Get-Service ssh-agent -ErrorAction SilentlyContinue
if ($agent -and $agent.Status -eq 'Running') { OK "ssh-agent service running" }
else { BAD "ssh-agent service not running" "As ADMINISTRATOR (without admin rights: 'Access is denied'): Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent — then ssh-add. With a passphrase-free key the service is not needed; what decides is 'ssh -T git@github.com'" }

if (Get-Command claude -ErrorAction SilentlyContinue) { OK "claude CLI present" } else { BAD "claude CLI missing" "install Claude Code" }

Write-Host ""
if ($fail -eq 0) { Write-Host "Preflight: ALL GREEN" } else { Write-Host "Preflight: RED — work through the items, then measure again" }
exit $fail
