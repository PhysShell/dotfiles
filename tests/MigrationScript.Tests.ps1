$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

BeforeAll {
    function Script:Invoke-GitForMigrationTests {
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

    function Script:New-MigrationTestRepository {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)]
            [string]$Prefix
        )

        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ($Prefix + '-' + [guid]::NewGuid().Guid)
        $repoPath = Join-Path $tempRoot 'repo'
        $toolsPath = Join-Path $repoPath 'tools'
        $modulePath = Join-Path $repoPath 'modules\GitAliases.Extras'

        New-Item -ItemType Directory -Path $toolsPath -Force | Out-Null
        New-Item -ItemType Directory -Path $modulePath -Force | Out-Null

        Copy-Item -Path $script:MigrationScriptSource -Destination (Join-Path $toolsPath 'migrate-gitaliases-extras.ps1') -Force

        Invoke-GitForMigrationTests -RepoPath $repoPath -Arguments @('init') | Out-Null
        Invoke-GitForMigrationTests -RepoPath $repoPath -Arguments @('config', 'user.email', 'test@example.com') | Out-Null
        Invoke-GitForMigrationTests -RepoPath $repoPath -Arguments @('config', 'user.name', 'Test User') | Out-Null
        Invoke-GitForMigrationTests -RepoPath $repoPath -Arguments @('config', 'commit.gpgsign', 'false') | Out-Null

        Set-Content -Path (Join-Path $modulePath 'GitAliases.Extras.psm1') -Value "function gsw { 'ok' }" -NoNewline -Encoding ascii
        Invoke-GitForMigrationTests -RepoPath $repoPath -Arguments @('add', '.') | Out-Null
        Invoke-GitForMigrationTests -RepoPath $repoPath -Arguments @('commit', '-m', 'init module') | Out-Null

        [pscustomobject]@{
            TempRoot = $tempRoot
            RepoPath = $repoPath
        }
    }

    [string]$script:RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..') |
        Select-Object -ExpandProperty Path -First 1
    $script:MigrationScriptSource = Join-Path $script:RepoRoot 'tools\migrate-gitaliases-extras.ps1'
}

Describe 'migrate-gitaliases-extras script' {
    It 'dry run succeeds and does not modify repository layout' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $context = New-MigrationTestRepository -Prefix 'migration-dry-run'
        try {
            Push-Location $context.RepoPath
            try {
                $output = & pwsh -NoProfile -File '.\tools\migrate-gitaliases-extras.ps1' -SubmoduleUrl 'git@github.com:example/GitAliases.Extras.git' 2>&1
                $exitCode = $LASTEXITCODE
            } finally {
                Pop-Location
            }

            $exitCode | Should -Be 0
            (($output | Out-String) -match 'Dry run complete') | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path $context.RepoPath 'modules\GitAliases.Extras\GitAliases.Extras.psm1')) | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path $context.RepoPath '.gitmodules')) | Should -BeFalse
        } finally {
            if (Test-Path -LiteralPath $context.TempRoot) {
                Remove-Item -Path $context.TempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'fails on dirty working tree without AllowDirty' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $context = New-MigrationTestRepository -Prefix 'migration-dirty'
        try {
            Set-Content -Path (Join-Path $context.RepoPath 'dirty.txt') -Value 'dirty' -NoNewline -Encoding ascii

            Push-Location $context.RepoPath
            try {
                $output = & pwsh -NoProfile -File '.\tools\migrate-gitaliases-extras.ps1' -SubmoduleUrl 'git@github.com:example/GitAliases.Extras.git' 2>&1
                $exitCode = $LASTEXITCODE
            } finally {
                Pop-Location
            }

            $exitCode | Should -Not -Be 0
            (($output | Out-String) -match 'Working tree is not clean') | Should -BeTrue
        } finally {
            if (Test-Path -LiteralPath $context.TempRoot) {
                Remove-Item -Path $context.TempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
