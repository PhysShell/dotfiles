[CmdletBinding()]
param(
    [string]$TestsPath = (Join-Path $PSScriptRoot '..\tests'),
    [switch]$SkipSubmoduleTests
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name Pester)) {
    throw "Pester is not installed. Run: Install-Module Pester -Scope CurrentUser -Force"
}

Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop

[string]$resolvedTestsPath = Resolve-Path -LiteralPath $TestsPath -ErrorAction Stop |
    Select-Object -ExpandProperty Path -First 1

[string]$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..') |
    Select-Object -ExpandProperty Path -First 1

$runPaths = @($resolvedTestsPath)
if (-not $SkipSubmoduleTests) {
    $submoduleTestsPath = Join-Path $repoRoot 'modules\GitAliases.Extras\tests'
    if (Test-Path -LiteralPath $submoduleTestsPath) {
        $runPaths += (Resolve-Path -LiteralPath $submoduleTestsPath |
            Select-Object -ExpandProperty Path -First 1)
    }
}

$config = [PesterConfiguration]::Default
$config.Run.Path = $runPaths
$config.Run.PassThru = $true
$config.Run.Exit = $false
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $repoRoot 'TestResults.xml'
$config.TestResult.OutputFormat = 'NUnitXml'

$gitEnvVars = @(
    'GIT_DIR',
    'GIT_WORK_TREE',
    'GIT_INDEX_FILE',
    'GIT_OBJECT_DIRECTORY',
    'GIT_ALTERNATE_OBJECT_DIRECTORIES',
    'GIT_COMMON_DIR',
    'GIT_PREFIX'
)

$savedGitEnv = @{}
foreach ($name in $gitEnvVars) {
    $item = Get-Item -Path "Env:$name" -ErrorAction SilentlyContinue
    if ($null -ne $item) {
        $savedGitEnv[$name] = $item.Value
        Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
    }
}

try {
    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0) {
        throw "Pester failed: $($result.FailedCount) test(s) failed."
    }
} finally {
    foreach ($name in $gitEnvVars) {
        Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
    }
    foreach ($name in $savedGitEnv.Keys) {
        Set-Item -Path "Env:$name" -Value $savedGitEnv[$name]
    }
}

Write-Host "Pester: all tests passed ($($result.PassedCount) passed)."
