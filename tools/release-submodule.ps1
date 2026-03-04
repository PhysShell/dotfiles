[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+([\-+][0-9A-Za-z\.-]+)?$')]
    [string]$Version,
    [string]$SubmodulePath = 'modules/git-aliases-extra',
    [string]$SubmoduleRemote = 'origin',
    [string]$RootRemote = 'origin',
    [string]$SubmoduleCommitMessage = '',
    [string]$RootCommitMessage = '',
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-GitCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [switch]$AllowFail
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git -C $RepoPath @Arguments 2>&1
    } finally {
        $ErrorActionPreference = $previousPreference
    }

    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if (-not $AllowFail -and $exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed in '$RepoPath' (exit=$exitCode): $text"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $text
    }
}

function Get-CurrentBranchOrNull {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )

    $result = Invoke-GitCommand -RepoPath $RepoPath -Arguments @('symbolic-ref', '--quiet', '--short', 'HEAD') -AllowFail
    if ($result.ExitCode -ne 0) {
        return $null
    }

    return $result.Output.Trim()
}

function Get-StatusPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )

    $result = Invoke-GitCommand -RepoPath $RepoPath -Arguments @('status', '--porcelain')
    if ([string]::IsNullOrWhiteSpace($result.Output)) {
        return @()
    }

    $lines = @($result.Output -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $paths = foreach ($line in $lines) {
        if ($line.Length -lt 4) {
            continue
        }

        $rawPath = $line.Substring(3).Trim()
        if ($rawPath -like '* -> *') {
            $rawPath = ($rawPath -split ' -> ')[-1].Trim()
        }

        if (-not [string]::IsNullOrWhiteSpace($rawPath)) {
            $rawPath.Replace('\', '/')
        }
    }

    return @($paths | Select-Object -Unique)
}

function Get-RelativePathSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $baseFull = [IO.Path]::GetFullPath($BasePath)
    $targetFull = [IO.Path]::GetFullPath($TargetPath)

    if (-not $baseFull.EndsWith([IO.Path]::DirectorySeparatorChar)) {
        $baseFull += [IO.Path]::DirectorySeparatorChar
    }

    $baseUri = [Uri]$baseFull
    $targetUri = [Uri]$targetFull

    if ($baseUri.Scheme -ne $targetUri.Scheme) {
        return $targetFull
    }

    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    $relativePath = [Uri]::UnescapeDataString($relativeUri.ToString())
    return $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git executable not found in PATH."
}

[string]$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..') |
    Select-Object -ExpandProperty Path -First 1

[string]$submoduleFullPath = if ([IO.Path]::IsPathRooted($SubmodulePath)) {
    Resolve-Path -LiteralPath $SubmodulePath |
        Select-Object -ExpandProperty Path -First 1
} else {
    Resolve-Path -LiteralPath (Join-Path $repoRoot $SubmodulePath) |
        Select-Object -ExpandProperty Path -First 1
}

$submoduleRelativePath = (Get-RelativePathSafe -BasePath $repoRoot -TargetPath $submoduleFullPath).Replace('\', '/')
if ($submoduleRelativePath.StartsWith('..')) {
    throw "Submodule path '$submoduleFullPath' is outside repo root '$repoRoot'."
}

$tagName = "v$Version"
$moduleName = Split-Path -Path $submoduleFullPath -Leaf
if (-not $SubmoduleCommitMessage) {
    $SubmoduleCommitMessage = "release: $tagName"
}
if (-not $RootCommitMessage) {
    $RootCommitMessage = "chore(submodule): bump $moduleName to $tagName"
}

$issues = New-Object System.Collections.Generic.List[string]

$rootRepoProbe = Invoke-GitCommand -RepoPath $repoRoot -Arguments @('rev-parse', '--is-inside-work-tree') -AllowFail
if ($rootRepoProbe.ExitCode -ne 0 -or $rootRepoProbe.Output.Trim() -ne 'true') {
    $issues.Add("Root path is not a git repository: '$repoRoot'")
}

$submoduleRepoProbe = Invoke-GitCommand -RepoPath $submoduleFullPath -Arguments @('rev-parse', '--is-inside-work-tree') -AllowFail
if ($submoduleRepoProbe.ExitCode -ne 0 -or $submoduleRepoProbe.Output.Trim() -ne 'true') {
    $issues.Add("Submodule path is not a git repository: '$submoduleFullPath'")
}

$rootBranch = Get-CurrentBranchOrNull -RepoPath $repoRoot
if ([string]::IsNullOrWhiteSpace($rootBranch)) {
    $issues.Add("Root repository is in detached HEAD state. Switch to a branch before release.")
}

$submoduleBranch = Get-CurrentBranchOrNull -RepoPath $submoduleFullPath
if ([string]::IsNullOrWhiteSpace($submoduleBranch)) {
    $issues.Add("Submodule repository is in detached HEAD state. Switch '$submoduleRelativePath' to a branch before release.")
}

$rootRemoteProbe = Invoke-GitCommand -RepoPath $repoRoot -Arguments @('remote', 'get-url', $RootRemote) -AllowFail
if ($rootRemoteProbe.ExitCode -ne 0) {
    $issues.Add("Root remote '$RootRemote' does not exist in '$repoRoot'.")
}

$submoduleRemoteProbe = Invoke-GitCommand -RepoPath $submoduleFullPath -Arguments @('remote', 'get-url', $SubmoduleRemote) -AllowFail
if ($submoduleRemoteProbe.ExitCode -ne 0) {
    $issues.Add("Submodule remote '$SubmoduleRemote' does not exist in '$submoduleFullPath'.")
}

$rootStatusPaths = @(Get-StatusPaths -RepoPath $repoRoot)
$unexpectedRootChanges = @($rootStatusPaths | Where-Object { $_ -ne $submoduleRelativePath })
if ($unexpectedRootChanges.Count -gt 0) {
    $issues.Add(
        ("Root repository has pending changes outside '$submoduleRelativePath': {0}" -f ($unexpectedRootChanges -join ', '))
    )
}

$rootConflicts = (Invoke-GitCommand -RepoPath $repoRoot -Arguments @('ls-files', '-u')).Output
if (-not [string]::IsNullOrWhiteSpace($rootConflicts)) {
    $issues.Add("Root repository has unresolved merge conflicts.")
}

$submoduleConflicts = (Invoke-GitCommand -RepoPath $submoduleFullPath -Arguments @('ls-files', '-u')).Output
if (-not [string]::IsNullOrWhiteSpace($submoduleConflicts)) {
    $issues.Add("Submodule repository has unresolved merge conflicts.")
}

$manifestPath = Join-Path $submoduleFullPath 'git-aliases-extra.psd1'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    $issues.Add("Submodule manifest not found: '$manifestPath'")
} else {
    try {
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $manifestVersion = [string]$manifest.ModuleVersion
        if ($manifestVersion -ne $Version) {
            $issues.Add("Manifest ModuleVersion '$manifestVersion' does not match requested version '$Version'.")
        }
    } catch {
        $issues.Add("Failed to parse manifest '$manifestPath': $($_.Exception.Message)")
    }
}

$changelogPath = Join-Path $submoduleFullPath 'CHANGELOG.md'
if (-not (Test-Path -LiteralPath $changelogPath)) {
    $issues.Add("Submodule changelog not found: '$changelogPath'")
} else {
    $changelogText = Get-Content -LiteralPath $changelogPath -Raw
    $versionHeaderPattern = "(?m)^## \[$([regex]::Escape($Version))\] - \d{4}-\d{2}-\d{2}$"
    if ($changelogText -notmatch $versionHeaderPattern) {
        $issues.Add("CHANGELOG.md must contain a heading like '## [$Version] - YYYY-MM-DD'.")
    }
}

$localTagProbe = Invoke-GitCommand -RepoPath $submoduleFullPath -Arguments @('rev-parse', '--verify', '--quiet', "refs/tags/$tagName") -AllowFail
if ($localTagProbe.ExitCode -eq 0) {
    $issues.Add("Tag '$tagName' already exists locally in submodule.")
}

$remoteTagProbe = Invoke-GitCommand -RepoPath $submoduleFullPath -Arguments @('ls-remote', '--tags', '--refs', $SubmoduleRemote, $tagName) -AllowFail
if ($remoteTagProbe.ExitCode -ne 0) {
    $issues.Add("Failed to query remote tag '$tagName' on '$SubmoduleRemote': $($remoteTagProbe.Output)")
} elseif (-not [string]::IsNullOrWhiteSpace($remoteTagProbe.Output)) {
    $issues.Add("Tag '$tagName' already exists on remote '$SubmoduleRemote'.")
}

if ($issues.Count -gt 0) {
    $message = @(
        "Preflight checks failed:"
        ($issues | ForEach-Object { " - $_" })
    ) -join [Environment]::NewLine

    throw $message
}

if (-not $SkipTests) {
    $submoduleTestsPath = Join-Path $submoduleFullPath 'tools\test.ps1'
    if (-not (Test-Path -LiteralPath $submoduleTestsPath)) {
        throw "Submodule test script not found: '$submoduleTestsPath'"
    }

    Write-Host "Running submodule tests in current shell..."
    & $submoduleTestsPath -CurrentShellOnly
}

$submoduleStatusBefore = @(Get-StatusPaths -RepoPath $submoduleFullPath)
$submoduleHadChanges = $submoduleStatusBefore.Count -gt 0

if ($submoduleHadChanges) {
    Write-Host ("Committing submodule changes in '{0}'..." -f $submoduleRelativePath)
    Invoke-GitCommand -RepoPath $submoduleFullPath -Arguments @('add', '-A') | Out-Null
    Invoke-GitCommand -RepoPath $submoduleFullPath -Arguments @('commit', '-m', $SubmoduleCommitMessage) | Out-Null
} else {
    Write-Host ("Submodule has no local changes. Commit step skipped in '{0}'." -f $submoduleRelativePath)
}

Write-Host ("Creating tag '{0}' in submodule..." -f $tagName)
Invoke-GitCommand -RepoPath $submoduleFullPath -Arguments @('tag', '-a', $tagName, '-m', "$moduleName $tagName") | Out-Null

Write-Host ("Pushing submodule branch '{0}' to '{1}'..." -f $submoduleBranch, $SubmoduleRemote)
Invoke-GitCommand -RepoPath $submoduleFullPath -Arguments @('push', $SubmoduleRemote, "HEAD:$submoduleBranch") | Out-Null

Write-Host ("Pushing submodule tag '{0}'..." -f $tagName)
Invoke-GitCommand -RepoPath $submoduleFullPath -Arguments @('push', $SubmoduleRemote, $tagName) | Out-Null

Write-Host ("Staging submodule pointer in root repo: '{0}'..." -f $submoduleRelativePath)
Invoke-GitCommand -RepoPath $repoRoot -Arguments @('add', '--', $submoduleRelativePath) | Out-Null

$stagedSubmodulePointer = (Invoke-GitCommand -RepoPath $repoRoot -Arguments @('diff', '--cached', '--name-only', '--', $submoduleRelativePath)).Output
$rootCommitted = $false

if (-not [string]::IsNullOrWhiteSpace($stagedSubmodulePointer)) {
    Write-Host ("Committing root repo update for submodule '{0}'..." -f $submoduleRelativePath)
    Invoke-GitCommand -RepoPath $repoRoot -Arguments @('commit', '-m', $RootCommitMessage) | Out-Null
    $rootCommitted = $true
} else {
    Write-Host "Root repo submodule pointer unchanged. Commit step skipped."
}

if ($rootCommitted) {
    Write-Host ("Pushing root branch '{0}' to '{1}'..." -f $rootBranch, $RootRemote)
    Invoke-GitCommand -RepoPath $repoRoot -Arguments @('push', $RootRemote, "HEAD:$rootBranch") | Out-Null
}

Write-Host ''
Write-Host "Release completed successfully."
Write-Host ("Submodule: {0}" -f $submoduleRelativePath)
Write-Host ("Version:   {0}" -f $Version)
Write-Host ("Tag:       {0}" -f $tagName)
Write-Host ("Branch:    {0}" -f $submoduleBranch)
