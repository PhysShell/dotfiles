[CmdletBinding()]
param(
    [string]$TestsPath = (Join-Path $PSScriptRoot '..\tests'),
    [switch]$SkipSubmoduleTests,
    [switch]$CurrentShellOnly,
    [string[]]$Shells = @('powershell', 'pwsh')
)

$ErrorActionPreference = 'Stop'

function Get-UserModulePath {
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        return (Join-Path $HOME 'Documents\WindowsPowerShell\Modules')
    } else {
        return (Join-Path $HOME 'Documents\PowerShell\Modules')
    }
}

$userModules = Get-UserModulePath
if ($env:PSModulePath -notlike "*$userModules*") {
    $env:PSModulePath = "$userModules;$env:PSModulePath"
}

[string]$resolvedTestsPath = Resolve-Path -LiteralPath $TestsPath -ErrorAction Stop |
    Select-Object -ExpandProperty Path -First 1

[string]$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..') |
    Select-Object -ExpandProperty Path -First 1

$runAllShells = -not $CurrentShellOnly
if ($env:GITHUB_ACTIONS -eq 'true' -or $env:CI -eq 'true') {
    $runAllShells = $false
}

if ($runAllShells) {
    $uniqueShells = @($Shells | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($uniqueShells.Count -eq 0) {
        throw 'No shells specified for test execution.'
    }

    $missingShells = @($uniqueShells | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
    if ($missingShells.Count -gt 0) {
        throw ("Missing required shell executable(s): {0}. Install both Windows PowerShell 5.1 ('powershell') and PowerShell 7+ ('pwsh'), or run -CurrentShellOnly." -f ($missingShells -join ', '))
    }

    foreach ($shellName in $uniqueShells) {
        Write-Host ("Running tests in {0}..." -f $shellName)
        $invokeArgs = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $PSCommandPath,
            '-TestsPath', $resolvedTestsPath,
            '-CurrentShellOnly'
        )
        if ($SkipSubmoduleTests) {
            $invokeArgs += '-SkipSubmoduleTests'
        }

        & $shellName @invokeArgs
        if ($LASTEXITCODE -ne 0) {
            throw ("Tests failed in shell: {0}" -f $shellName)
        }
    }

    Write-Host ("Pester: all tests passed in shells: {0}." -f ($uniqueShells -join ', '))
    return
}

if (-not (Get-Module -ListAvailable -Name Pester)) {
    throw "Pester is not installed. Run: Install-Module Pester -Scope CurrentUser -Force"
}

Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop

$runPaths = @($resolvedTestsPath)
if (-not $SkipSubmoduleTests) {
    $submoduleTestsPath = Join-Path $repoRoot 'modules\git-aliases-extra\tests'
    if (Test-Path -LiteralPath $submoduleTestsPath) {
        $runPaths += (Resolve-Path -LiteralPath $submoduleTestsPath |
            Select-Object -ExpandProperty Path -First 1)
    }
}

$config = [PesterConfiguration]::Default
$config.Run.Path = $runPaths
$config.Run.PassThru = $true
$config.Run.Exit = $false
$isCi = ($env:GITHUB_ACTIONS -eq 'true' -or $env:CI -eq 'true')
$config.Output.Verbosity = if ($isCi) { 'Detailed' } else { 'Normal' }
$config.TestResult.Enabled = $isCi
if ($isCi) {
    $config.TestResult.OutputPath = Join-Path $repoRoot 'TestResults.xml'
    $config.TestResult.OutputFormat = 'NUnitXml'
}

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
    try {
        $result = Invoke-Pester -Configuration $config -ErrorAction Stop
    } catch {
        throw "Invoke-Pester failed: $($_.Exception.Message)"
    }

    if ($null -eq $result) {
        throw 'Invoke-Pester returned no result.'
    }

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
