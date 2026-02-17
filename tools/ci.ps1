[CmdletBinding()]
param(
    [switch]$LintOnly,
    [switch]$TestOnly
)

$ErrorActionPreference = 'Stop'

if ($LintOnly -and $TestOnly) {
    throw "Use either -LintOnly or -TestOnly, not both."
}

[string]$root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..') |
    Select-Object -ExpandProperty Path -First 1

if (-not $TestOnly) {
    & (Join-Path $root 'tools\lint.ps1') -Path $root
}

if (-not $LintOnly) {
    & (Join-Path $root 'tools\test.ps1') -TestsPath (Join-Path $root 'tests')
}

Write-Host 'CI checks completed.'
