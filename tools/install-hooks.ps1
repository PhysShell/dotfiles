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

New-Item -ItemType Directory -Path $hookDir -Force | Out-Null

$hookNames = @('pre-commit', 'commit-msg')
foreach ($hookName in $hookNames) {
    $source = Join-Path $root ("tools\hooks\{0}" -f $hookName)
    $destination = Join-Path $hookDir $hookName

    if (-not (Test-Path $source)) {
        throw "Hook source not found: $source"
    }

    Copy-Item -Path $source -Destination $destination -Force
    Write-Host ("Installed {0} hook: {1}" -f $hookName, $destination)
}
