function Ensure-Module($name, [Version]$min = $null) {
  $ok = Get-Module -ListAvailable $name | Where-Object { -not $min -or $_.Version -ge $min }
  if (-not $ok) { Install-Module $name -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck }
}

function Ensure-GitGlobalConfig([string]$Key, [string]$Value) {
  $current = git config --global --get $Key 2>$null
  if ($current -ne $Value) {
    git config --global $Key $Value
  }
}

function Ensure-GitSubmodules([string]$RepoRoot) {
  $gitmodulesPath = Join-Path $RepoRoot '.gitmodules'
  if (-not (Test-Path -LiteralPath $gitmodulesPath)) {
    return
  }

  $null = git -C $RepoRoot submodule sync --recursive
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to sync git submodules in '$RepoRoot'."
  }

  $null = git -C $RepoRoot submodule update --init --recursive
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to initialize/update git submodules in '$RepoRoot'."
  }
}

# PSReadLine is required for Windows PowerShell 5.1; it's already built into PowerShell Core (pwsh)
if ($PSVersionTable.PSEdition -ne 'Core') { Ensure-Module PSReadLine ([Version]'2.2.6') }

Ensure-Module posh-git
Ensure-Module git-aliases

# Git push defaults:
# - first push of a new branch auto-creates upstream tracking
# - default push target is the current branch to origin
Ensure-GitGlobalConfig 'push.autoSetupRemote' 'true'
Ensure-GitGlobalConfig 'push.default' 'current'
Ensure-GitGlobalConfig 'remote.pushDefault' 'origin'

$repoRoot = Resolve-Path -LiteralPath $PSScriptRoot | Select-Object -ExpandProperty Path -First 1
Ensure-GitSubmodules -RepoRoot $repoRoot

Write-Host "Bootstrap done. Restart PowerShell."

