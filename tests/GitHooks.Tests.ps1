$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

BeforeAll {
    function Script:Invoke-GitForHookTests {
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

        [pscustomobject]@{
            ExitCode = $exitCode
            Output   = $text
        }
    }

    function Script:New-HookTestRepository {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)]
            [string]$Prefix
        )

        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ($Prefix + '-' + [guid]::NewGuid().Guid)
        $repoPath = Join-Path $tempRoot 'repo'

        New-Item -ItemType Directory -Path $repoPath -Force | Out-Null

        Invoke-GitForHookTests -RepoPath $repoPath -Arguments @('init') | Out-Null
        Invoke-GitForHookTests -RepoPath $repoPath -Arguments @('config', 'user.email', 'test@example.com') | Out-Null
        Invoke-GitForHookTests -RepoPath $repoPath -Arguments @('config', 'user.name', 'Test User') | Out-Null
        Invoke-GitForHookTests -RepoPath $repoPath -Arguments @('config', 'commit.gpgsign', 'false') | Out-Null

        $toolsPath = Join-Path $repoPath 'tools'
        New-Item -ItemType Directory -Path $toolsPath -Force | Out-Null
        $ciScriptPath = Join-Path $toolsPath 'ci.ps1'
        @'
Set-Content -Path '.git/ci-ran' -Value 'ran' -NoNewline -Encoding ascii
'@ | Set-Content -Path $ciScriptPath -Encoding ascii

        Set-Content -Path (Join-Path $repoPath 'README.md') -Value 'root' -NoNewline -Encoding ascii
        Invoke-GitForHookTests -RepoPath $repoPath -Arguments @('add', 'README.md', 'tools/ci.ps1') | Out-Null
        Invoke-GitForHookTests -RepoPath $repoPath -Arguments @('commit', '-m', 'init') | Out-Null

        $hooksPath = Join-Path $repoPath '.git\hooks'
        Copy-Item -Path $script:PreCommitHookSource -Destination (Join-Path $hooksPath 'pre-commit') -Force
        Copy-Item -Path $script:CommitMsgHookSource -Destination (Join-Path $hooksPath 'commit-msg') -Force

        [pscustomobject]@{
            TempRoot   = $tempRoot
            RepoPath   = $repoPath
            MarkerPath = Join-Path $repoPath '.git\ci-ran'
        }
    }

    [string]$script:RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..') |
        Select-Object -ExpandProperty Path -First 1
    $script:PreCommitHookSource = Join-Path $script:RepoRoot 'tools\hooks\pre-commit'
    $script:CommitMsgHookSource = Join-Path $script:RepoRoot 'tools\hooks\commit-msg'
}

Describe 'commit hooks integration' {
    It 'skips checks when commit message contains <Tag>' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) -TestCases @(
        @{ Tag = '[skip precommit hook]' },
        @{ Tag = '[skip pch]' }
    ) {
        param([string]$Tag)

        $context = New-HookTestRepository -Prefix 'hook-skip-tag'
        try {
            Set-Content -Path (Join-Path $context.RepoPath 'feature.txt') -Value 'feature' -NoNewline -Encoding ascii
            Invoke-GitForHookTests -RepoPath $context.RepoPath -Arguments @('add', 'feature.txt') | Out-Null
            Invoke-GitForHookTests -RepoPath $context.RepoPath -Arguments @('commit', '-m', "feature $Tag") | Out-Null

            (Test-Path -LiteralPath $context.MarkerPath) | Should -BeFalse
        } finally {
            if (Test-Path -LiteralPath $context.TempRoot) {
                Remove-Item -Path $context.TempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'runs checks for a normal commit message' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $context = New-HookTestRepository -Prefix 'hook-normal-commit'
        try {
            Set-Content -Path (Join-Path $context.RepoPath 'feature.txt') -Value 'feature' -NoNewline -Encoding ascii
            Invoke-GitForHookTests -RepoPath $context.RepoPath -Arguments @('add', 'feature.txt') | Out-Null
            Invoke-GitForHookTests -RepoPath $context.RepoPath -Arguments @('commit', '-m', 'feature commit') | Out-Null

            (Test-Path -LiteralPath $context.MarkerPath) | Should -BeTrue
        } finally {
            if (Test-Path -LiteralPath $context.TempRoot) {
                Remove-Item -Path $context.TempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'skips checks for allow-empty commit with no file changes' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $context = New-HookTestRepository -Prefix 'hook-allow-empty'
        try {
            Invoke-GitForHookTests -RepoPath $context.RepoPath -Arguments @('commit', '--allow-empty', '-m', 'empty commit') | Out-Null

            (Test-Path -LiteralPath $context.MarkerPath) | Should -BeFalse
        } finally {
            if (Test-Path -LiteralPath $context.TempRoot) {
                Remove-Item -Path $context.TempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
