[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubmoduleUrl,
    [string]$SubmoduleBranch = 'main',
    [string]$ModulePath = 'modules/git-aliases-extra',
    [switch]$PushSplit,
    [switch]$Apply,
    [switch]$AllowDirty
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Git {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git -C $RepoRoot @Arguments 2>&1
    } finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($LASTEXITCODE -ne 0) {
        $text = ($output | Out-String).Trim()
        throw "git $($Arguments -join ' ') failed (exit=$LASTEXITCODE): $text"
    }

    return ($output | Out-String).Trim()
}

[string]$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..') |
    Select-Object -ExpandProperty Path -First 1
[string]$moduleFullPath = Join-Path $repoRoot $ModulePath

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
    throw "Not a git repository: $repoRoot"
}

if (-not (Test-Path -LiteralPath $moduleFullPath)) {
    throw "Module path not found: $moduleFullPath"
}

if (-not $AllowDirty) {
    $status = Invoke-Git -RepoRoot $repoRoot -Arguments @('status', '--porcelain')
    if ($status) {
        throw "Working tree is not clean. Commit or stash changes, or rerun with -AllowDirty."
    }
}

Write-Host "Creating split history for '$ModulePath'..."
$splitOutput = Invoke-Git -RepoRoot $repoRoot -Arguments @('subtree', 'split', "--prefix=$ModulePath", 'HEAD')
$splitCommit = ($splitOutput -split "`r?`n" | Where-Object { $_ -match '^[0-9a-f]{40}$' } | Select-Object -Last 1)
if (-not $splitCommit) {
    throw "Could not resolve split commit from git subtree output."
}
Write-Host "Split commit: $splitCommit"

if ($PushSplit) {
    Write-Host "Pushing split history to '$SubmoduleUrl' branch '$SubmoduleBranch'..."
    Invoke-Git -RepoRoot $repoRoot -Arguments @('push', $SubmoduleUrl, "$($splitCommit):refs/heads/$SubmoduleBranch") | Out-Null
}

if (-not $Apply) {
    Write-Host ''
    Write-Host 'Dry run complete. Next command:'
    Write-Host ("  .\tools\migrate-git-aliases-extra.ps1 -SubmoduleUrl '{0}' -SubmoduleBranch '{1}' -PushSplit -Apply" -f $SubmoduleUrl, $SubmoduleBranch)
    Write-Host ''
    Write-Host 'This will:'
    Write-Host ("  1) keep history via subtree split for {0}" -f $ModulePath)
    Write-Host ("  2) replace {0} with a git submodule" -f $ModulePath)
    exit 0
}

if (-not $PushSplit) {
    Write-Warning "You used -Apply without -PushSplit. Ensure branch '$SubmoduleBranch' already exists in '$SubmoduleUrl'."
}

Write-Host "Replacing '$ModulePath' with a submodule..."
Invoke-Git -RepoRoot $repoRoot -Arguments @('rm', '-r', '--', $ModulePath) | Out-Null
Invoke-Git -RepoRoot $repoRoot -Arguments @('submodule', 'add', '-b', $SubmoduleBranch, $SubmoduleUrl, $ModulePath) | Out-Null
Invoke-Git -RepoRoot $repoRoot -Arguments @('submodule', 'sync', '--recursive') | Out-Null
Invoke-Git -RepoRoot $repoRoot -Arguments @('submodule', 'update', '--init', '--recursive', '--', $ModulePath) | Out-Null

Write-Host ''
Write-Host 'Migration completed.'
Write-Host 'Review and commit:'
Write-Host '  git status'
Write-Host "  git commit -m 'Extract git-aliases-extra to submodule'"
