[CmdletBinding()]
param(
    [string]$Path = ''
)

$ErrorActionPreference = 'Stop'

function Get-RepoRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $fullRoot = [IO.Path]::GetFullPath($RepoRoot)
    $fullPath = [IO.Path]::GetFullPath($FilePath)
    if ($fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $relative = $fullPath.Substring($fullRoot.Length).TrimStart('\', '/')
        return ($relative -replace '\\', '/')
    }

    return $FilePath
}

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    throw "PSScriptAnalyzer is not installed. Run: Install-Module PSScriptAnalyzer -Scope CurrentUser -Force"
}

Import-Module PSScriptAnalyzer -ErrorAction Stop

if (-not $Path) {
    $Path = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..') |
        Select-Object -ExpandProperty Path -First 1
}

[string]$repoRoot = Resolve-Path -LiteralPath $Path | Select-Object -ExpandProperty Path -First 1
$settings = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
if (-not (Test-Path $settings)) {
    throw "Missing PSScriptAnalyzerSettings.psd1 at repo root: $repoRoot"
}

$targets = @(
    (Join-Path $repoRoot 'modules'),
    (Join-Path $repoRoot 'tests'),
    (Join-Path $repoRoot 'tools'),
    (Join-Path $repoRoot 'bootstrap.ps1'),
    (Join-Path $repoRoot 'profile.ps1')
) | Where-Object { Test-Path $_ }

$results = @()
foreach ($target in $targets) {
    $results += Invoke-ScriptAnalyzer -Path $target -Recurse -Settings $settings
}

if ($results -and $results.Count -gt 0) {
    foreach ($result in $results) {
        if ($env:GITHUB_ACTIONS -eq 'true') {
            $file = Get-RepoRelativePath -RepoRoot $repoRoot -FilePath $result.ScriptName
            $line = if ($result.Line) { $result.Line } else { 1 }
            $column = if ($result.Column) { $result.Column } else { 1 }
            $message = ($result.Message -replace "`r?`n", ' ')
            $rule = $result.RuleName
            $severity = $result.Severity.ToString().ToLowerInvariant()
            if ($severity -eq 'error') {
                Write-Host "::error file=$file,line=$line,col=$column,title=$rule::$message"
            } else {
                Write-Host "::warning file=$file,line=$line,col=$column,title=$rule::$message"
            }
        }
    }

    $results |
        Sort-Object ScriptName, Line, RuleName |
        Format-Table Severity, RuleName, ScriptName, Line, Column, Message -AutoSize |
        Out-String |
        Write-Host

    throw "PSScriptAnalyzer found issues: $($results.Count)"
}

Write-Host 'PSScriptAnalyzer: no issues found.'
