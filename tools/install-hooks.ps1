[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

[string]$root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..') |
    Select-Object -ExpandProperty Path -First 1
$gitDir = (git -C $root rev-parse --git-dir 2>$null)
if (-not $gitDir) {
    throw "Not a git repository: $root"
}

$gitDir = $gitDir.Trim()
$hookDir = if ([IO.Path]::IsPathRooted($gitDir)) {
    Join-Path $gitDir 'hooks'
} else {
    Join-Path $root $gitDir 'hooks'
}

$source = Join-Path $root 'tools\hooks\pre-commit'
$destination = Join-Path $hookDir 'pre-commit'

if (-not (Test-Path $source)) {
    throw "Hook source not found: $source"
}

New-Item -ItemType Directory -Path $hookDir -Force | Out-Null
Copy-Item -Path $source -Destination $destination -Force

Write-Host "Installed pre-commit hook: $destination"
