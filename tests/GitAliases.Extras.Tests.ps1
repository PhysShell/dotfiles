$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$script:HasGcoAlias = [bool](Get-Command gco -ErrorAction SilentlyContinue)

BeforeAll {
    function Script:Invoke-GitCommand {
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
            Output = $text
        }
    }

    function Script:Find-BlobPrefixCollision {
        [CmdletBinding()]
        param(
            [string]$Prefix = '8695',
            [int]$MaxAttempts = 2000000
        )

        $sha1 = [System.Security.Cryptography.SHA1]::Create()
        try {
            for ($i = 0; $i -lt $MaxAttempts; $i++) {
                $content = "collision-$i"
                $contentBytes = [Text.Encoding]::ASCII.GetBytes($content)
                $headerBytes = [Text.Encoding]::ASCII.GetBytes("blob $($contentBytes.Length)`0")

                $payload = New-Object byte[] ($headerBytes.Length + $contentBytes.Length)
                [Buffer]::BlockCopy($headerBytes, 0, $payload, 0, $headerBytes.Length)
                [Buffer]::BlockCopy($contentBytes, 0, $payload, $headerBytes.Length, $contentBytes.Length)

                $hashBytes = $sha1.ComputeHash($payload)
                $hash = ([BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
                if ($hash.StartsWith($Prefix)) {
                    return [pscustomobject]@{
                        Content = $content
                        Hash = $hash
                    }
                }
            }
        } finally {
            $sha1.Dispose()
        }

        throw "Could not find blob hash prefix '$Prefix' within $MaxAttempts attempts."
    }

    [string]$script:RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..') |
        Select-Object -ExpandProperty Path -First 1
    $script:ModuleManifest = Join-Path $script:RepoRoot 'modules\GitAliases.Extras\GitAliases.Extras.psd1'

    if (Get-Module -ListAvailable -Name git-aliases) {
        Import-Module git-aliases -DisableNameChecking -ErrorAction SilentlyContinue
    }

    Import-Module $script:ModuleManifest -Force
    $script:HasGcoAlias = [bool](Get-Command gco -ErrorAction SilentlyContinue)
}

AfterAll {
    Remove-Module GitAliases.Extras -Force -ErrorAction SilentlyContinue
}

Describe 'GitAliases.Extras module' {
    It 'imports successfully' {
        Get-Module GitAliases.Extras | Should -Not -BeNullOrEmpty
    }

    It 'exports expected commands' {
        Get-Command Test-InGitRepo -ErrorAction Stop | Should -Not -BeNullOrEmpty
        Get-Command UpMerge -ErrorAction Stop | Should -Not -BeNullOrEmpty
        Get-Command UpRebase -ErrorAction Stop | Should -Not -BeNullOrEmpty
        Get-Command gfp -ErrorAction Stop | Should -Not -BeNullOrEmpty
        Get-Command gsw -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }

    It 'Test-InGitRepo returns a boolean value outside or inside a repository' {
        (Test-InGitRepo).GetType().Name | Should -Be 'Boolean'
    }
}

Describe 'gfp integration' {
    It 'creates series.mbox using default base branch resolution' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("gfp-default-" + [guid]::NewGuid().Guid)
        $remotePath = Join-Path $tempRoot 'remote.git'
        $workPath = Join-Path $tempRoot 'work'

        New-Item -ItemType Directory -Path $workPath -Force | Out-Null
        try {
            Invoke-GitCommand -RepoPath $tempRoot -Arguments @('init', '--bare', $remotePath) | Out-Null
            Invoke-GitCommand -RepoPath $tempRoot -Arguments @('init', $workPath) | Out-Null

            Invoke-GitCommand -RepoPath $workPath -Arguments @('config', 'user.email', 'test@example.com') | Out-Null
            Invoke-GitCommand -RepoPath $workPath -Arguments @('config', 'user.name', 'Test User') | Out-Null
            Invoke-GitCommand -RepoPath $workPath -Arguments @('config', 'commit.gpgsign', 'false') | Out-Null

            Set-Content -Path (Join-Path $workPath 'README.md') -Value 'root' -NoNewline -Encoding ascii
            Invoke-GitCommand -RepoPath $workPath -Arguments @('add', 'README.md') | Out-Null
            Invoke-GitCommand -RepoPath $workPath -Arguments @('commit', '-m', 'init main') | Out-Null
            Invoke-GitCommand -RepoPath $workPath -Arguments @('branch', '-M', 'main') | Out-Null
            Invoke-GitCommand -RepoPath $workPath -Arguments @('remote', 'add', 'origin', $remotePath) | Out-Null
            Invoke-GitCommand -RepoPath $workPath -Arguments @('push', '-u', 'origin', 'main') | Out-Null

            Add-Content -Path (Join-Path $workPath 'README.md') -Value "`nfeature-from-main"
            Invoke-GitCommand -RepoPath $workPath -Arguments @('add', 'README.md') | Out-Null
            Invoke-GitCommand -RepoPath $workPath -Arguments @('commit', '-m', 'feature main patch') | Out-Null

            Push-Location $workPath
            try {
                $mboxPath = gfp
            } finally {
                Pop-Location
            }

            $expectedPath = Join-Path $workPath 'series.mbox'
            $mboxPath | Should -Be $expectedPath
            (Test-Path -LiteralPath $expectedPath) | Should -BeTrue

            $mboxContent = Get-Content -LiteralPath $expectedPath -Raw
            $mboxContent | Should -Match 'Subject: \[PATCH'
            $mboxContent | Should -Match 'feature main patch'
        } finally {
            if (Test-Path $tempRoot) {
                Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'supports explicit target branch and custom output mbox path' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("gfp-custom-" + [guid]::NewGuid().Guid)
        $remotePath = Join-Path $tempRoot 'remote.git'
        $workPath = Join-Path $tempRoot 'work'

        New-Item -ItemType Directory -Path $workPath -Force | Out-Null
        try {
            Invoke-GitCommand -RepoPath $tempRoot -Arguments @('init', '--bare', $remotePath) | Out-Null
            Invoke-GitCommand -RepoPath $tempRoot -Arguments @('init', $workPath) | Out-Null

            Invoke-GitCommand -RepoPath $workPath -Arguments @('config', 'user.email', 'test@example.com') | Out-Null
            Invoke-GitCommand -RepoPath $workPath -Arguments @('config', 'user.name', 'Test User') | Out-Null
            Invoke-GitCommand -RepoPath $workPath -Arguments @('config', 'commit.gpgsign', 'false') | Out-Null

            Set-Content -Path (Join-Path $workPath 'README.md') -Value 'root' -NoNewline -Encoding ascii
            Invoke-GitCommand -RepoPath $workPath -Arguments @('add', 'README.md') | Out-Null
            Invoke-GitCommand -RepoPath $workPath -Arguments @('commit', '-m', 'init master') | Out-Null
            Invoke-GitCommand -RepoPath $workPath -Arguments @('branch', '-M', 'master') | Out-Null
            Invoke-GitCommand -RepoPath $workPath -Arguments @('remote', 'add', 'origin', $remotePath) | Out-Null
            Invoke-GitCommand -RepoPath $workPath -Arguments @('push', '-u', 'origin', 'master') | Out-Null

            Add-Content -Path (Join-Path $workPath 'README.md') -Value "`nfeature-custom"
            Invoke-GitCommand -RepoPath $workPath -Arguments @('add', 'README.md') | Out-Null
            Invoke-GitCommand -RepoPath $workPath -Arguments @('commit', '-m', 'custom output patch') | Out-Null

            Push-Location $workPath
            try {
                $mboxPath = gfp master 'artifacts\custom-series.mbox'
            } finally {
                Pop-Location
            }

            $expectedPath = Join-Path $workPath 'artifacts\custom-series.mbox'
            $mboxPath | Should -Be $expectedPath
            (Test-Path -LiteralPath $expectedPath) | Should -BeTrue

            $mboxContent = Get-Content -LiteralPath $expectedPath -Raw
            $mboxContent | Should -Match 'Subject: \[PATCH'
            $mboxContent | Should -Match 'custom output patch'
        } finally {
            if (Test-Path $tempRoot) {
                Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'gsw integration' {
    It 'completes long options for gsw alias' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Push-Location $script:RepoRoot
        try {
            $line = 'gsw --'
            $result = TabExpansion2 -inputScript $line -cursorColumn $line.Length
        } finally {
            Pop-Location
        }

        $result.CompletionMatches.Count | Should -BeGreaterThan 0
        $completionTexts = @($result.CompletionMatches | Select-Object -ExpandProperty CompletionText)
        $completionTexts | Should -Contain '--track'
    }

    It 'completes long options for gco alias from git-aliases module' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue) -or -not $script:HasGcoAlias) {
        Push-Location $script:RepoRoot
        try {
            $line = 'gco --'
            $result = TabExpansion2 -inputScript $line -cursorColumn $line.Length
        } finally {
            Pop-Location
        }

        $result.CompletionMatches.Count | Should -BeGreaterThan 0
        $completionTexts = @($result.CompletionMatches | Select-Object -ExpandProperty CompletionText)
        $completionTexts | Should -Contain '--detach'
    }

    It 'returns PowerShell-safe completion text for branches starting with # when escaped prefix is used' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("gsw-complete-" + [guid]::NewGuid().Guid)
        $repoPath = Join-Path $tempRoot 'repo'

        New-Item -ItemType Directory -Path $repoPath -Force | Out-Null
        try {
            Invoke-GitCommand -RepoPath $tempRoot -Arguments @('init', $repoPath) | Out-Null
            Invoke-GitCommand -RepoPath $repoPath -Arguments @('config', 'user.email', 'test@example.com') | Out-Null
            Invoke-GitCommand -RepoPath $repoPath -Arguments @('config', 'user.name', 'Test User') | Out-Null
            Invoke-GitCommand -RepoPath $repoPath -Arguments @('config', 'commit.gpgsign', 'false') | Out-Null

            Set-Content -Path (Join-Path $repoPath 'README.md') -Value 'root' -NoNewline -Encoding ascii
            Invoke-GitCommand -RepoPath $repoPath -Arguments @('add', 'README.md') | Out-Null
            Invoke-GitCommand -RepoPath $repoPath -Arguments @('commit', '-m', 'init') | Out-Null
            Invoke-GitCommand -RepoPath $repoPath -Arguments @('branch', '-M', 'main') | Out-Null
            Invoke-GitCommand -RepoPath $repoPath -Arguments @('branch', '#8698') | Out-Null

            Push-Location $repoPath
            try {
                $line = 'gsw `#'
                $result = TabExpansion2 -inputScript $line -cursorColumn $line.Length
            } finally {
                Pop-Location
            }

            $result.CompletionMatches.Count | Should -BeGreaterThan 0
            $completionTexts = @($result.CompletionMatches | Select-Object -ExpandProperty CompletionText)
            $completionTexts | Should -Contain "'#8698'"
        } finally {
            if (Test-Path $tempRoot) {
                Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'handles remote-only numeric branch when native switch is ambiguous' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("gsw-integration-" + [guid]::NewGuid().Guid)
        $remotePath = Join-Path $tempRoot 'remote.git'
        $seedPath = Join-Path $tempRoot 'seed'
        $clonePath = Join-Path $tempRoot 'clone'

        New-Item -ItemType Directory -Path $seedPath -Force | Out-Null
        try {
            Invoke-GitCommand -RepoPath $tempRoot -Arguments @('init', '--bare', $remotePath) | Out-Null
            Invoke-GitCommand -RepoPath $tempRoot -Arguments @('init', $seedPath) | Out-Null

            Invoke-GitCommand -RepoPath $seedPath -Arguments @('config', 'user.email', 'test@example.com') | Out-Null
            Invoke-GitCommand -RepoPath $seedPath -Arguments @('config', 'user.name', 'Test User') | Out-Null
            Invoke-GitCommand -RepoPath $seedPath -Arguments @('config', 'commit.gpgsign', 'false') | Out-Null

            Set-Content -Path (Join-Path $seedPath 'README.md') -Value 'root' -NoNewline -Encoding ascii
            Invoke-GitCommand -RepoPath $seedPath -Arguments @('add', 'README.md') | Out-Null
            Invoke-GitCommand -RepoPath $seedPath -Arguments @('commit', '-m', 'init') | Out-Null
            Invoke-GitCommand -RepoPath $seedPath -Arguments @('branch', '-M', 'main') | Out-Null
            Invoke-GitCommand -RepoPath $seedPath -Arguments @('remote', 'add', 'origin', $remotePath) | Out-Null
            Invoke-GitCommand -RepoPath $seedPath -Arguments @('push', '-u', 'origin', 'main') | Out-Null

            Invoke-GitCommand -RepoPath $seedPath -Arguments @('switch', '-c', '8695') | Out-Null
            Set-Content -Path (Join-Path $seedPath 'feature.txt') -Value 'feature' -NoNewline -Encoding ascii
            Invoke-GitCommand -RepoPath $seedPath -Arguments @('add', 'feature.txt') | Out-Null
            Invoke-GitCommand -RepoPath $seedPath -Arguments @('commit', '-m', 'feature') | Out-Null
            Invoke-GitCommand -RepoPath $seedPath -Arguments @('push', '-u', 'origin', '8695') | Out-Null

            Invoke-GitCommand -RepoPath $tempRoot -Arguments @('clone', $remotePath, $clonePath) | Out-Null
            Invoke-GitCommand -RepoPath $clonePath -Arguments @('config', 'commit.gpgsign', 'false') | Out-Null

            $collision = Find-BlobPrefixCollision -Prefix '8695'
            $collisionFile = Join-Path $clonePath 'collision.txt'
            Set-Content -Path $collisionFile -Value $collision.Content -NoNewline -Encoding ascii

            $written = (Invoke-GitCommand -RepoPath $clonePath -Arguments @('hash-object', '-w', $collisionFile)).Output
            $written | Should -Be $collision.Hash

            (Invoke-GitCommand -RepoPath $clonePath -Arguments @('cat-file', '-t', '8695')).Output | Should -Be 'blob'

            Push-Location $clonePath
            try {
                $previousPreference = $ErrorActionPreference
                $ErrorActionPreference = 'Continue'
                try {
                    $nativeSwitchOutput = & git switch 8695 2>&1 | Out-String
                    $nativeSwitchExitCode = $LASTEXITCODE
                } finally {
                    $ErrorActionPreference = $previousPreference
                }

                $nativeSwitchExitCode | Should -Not -Be 0
                $nativeSwitchOutput.Trim() | Should -Match 'unable to read tree|non-commit|invalid reference'

                $previousPreference = $ErrorActionPreference
                $ErrorActionPreference = 'Continue'
                try {
                    gsw 8695 | Out-Null
                    $gswExitCode = $LASTEXITCODE
                } finally {
                    $ErrorActionPreference = $previousPreference
                }

                $gswExitCode | Should -Be 0
            } finally {
                Pop-Location
            }

            (Invoke-GitCommand -RepoPath $clonePath -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')).Output | Should -Be '8695'
            (Invoke-GitCommand -RepoPath $clonePath -Arguments @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')).Output | Should -Be 'origin/8695'
        } finally {
            if (Test-Path $tempRoot) {
                Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
