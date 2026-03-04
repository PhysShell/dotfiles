[CmdletBinding()]
param(
    [switch]$LintOnly,
    [switch]$TestOnly,
    [switch]$CurrentShellOnly
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
    $testArgs = @{
        TestsPath = (Join-Path $root 'tests')
    }
    if ($CurrentShellOnly) {
        $testArgs.CurrentShellOnly = $true
    }
    & (Join-Path $root 'tools\test.ps1') @testArgs
}

Write-Host 'CI checks completed.'
