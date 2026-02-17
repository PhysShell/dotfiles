# ===================================================================
# GitAliases.Extras.psm1
#
# Extends posh-git and git-aliases with custom functions and
# adds robust tab completion for all git aliases.
#
# Mainly inspired by: https://github.com/zh30/zsh-shortcut-git
# ===================================================================

# --- Custom Helper Functions ---
function Test-InGitRepo {
    try {
        git rev-parse --is-inside-work-tree *> $null
        $true
    } catch {
        $false
    }
}

function Test-GitInProgress {
    if (-not (Test-InGitRepo)) { return $false }
    $gitDir = git rev-parse --git-dir
    $inProgressFiles = @("MERGE_HEAD", "REBASE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG")
    foreach ($file in $inProgressFiles) {
        if (Test-Path (Join-Path $gitDir $file)) { return $true }
    }
    $false
}

function Test-WorkingTreeClean {
    if (-not (Test-InGitRepo)) { return $false }
    # Checks for both unstaged and staged changes.
    & git diff --quiet --exit-code
    $isClean = ($LASTEXITCODE -eq 0)
    & git diff --cached --quiet --exit-code
    $isClean = $isClean -and ($LASTEXITCODE -eq 0)
    return $isClean
}

function Get-CurrentBranch {
    if (Test-InGitRepo) {
        $branch = git rev-parse --abbrev-ref HEAD
        if ($branch -ne "HEAD") {
            return $branch.Trim()
        }
    }
    return $null
}

function Test-GitRefExists {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RefName
    )
    & git show-ref --verify --quiet $RefName
    return ($LASTEXITCODE -eq 0)
}


# --- Custom Git Command Functions ---
function UpMerge {
    [CmdletBinding()]
    param(
        [string]$Src = "origin/main",
        [switch]$AllowDirty, [switch]$AllowInProgress, [switch]$NoFetch, [switch]$NoFF
    )
    if (-not (Test-InGitRepo)) { throw "Not a git repository." }
    $tgt = Get-CurrentBranch; if (-not $tgt) { throw "Detached HEAD. Cannot merge." }
    if (-not $AllowInProgress -and (Test-GitInProgress)) { throw "Another git operation is in progress." }
    if (-not $AllowDirty -and -not (Test-WorkingTreeClean)) { throw "Working tree is not clean." }
    if (-not $NoFetch) { git fetch --all --prune; if ($LASTEXITCODE -ne 0) { throw "git fetch failed." } }
    $msg = "chore(sync): merge $Src into $tgt"
    if ($NoFF) { git merge --no-ff --no-edit $Src -m $msg } else { git merge --no-edit $Src -m $msg }
}

function UpRebase {
    [CmdletBinding()]
    param(
        [string]$Src = "origin/main",
        [switch]$AllowDirty, [switch]$AllowInProgress, [switch]$NoFetch, [switch]$Autostash
    )
    if (-not (Test-InGitRepo)) { throw "Not a git repository." }
    $tgt = Get-CurrentBranch; if (-not $tgt) { throw "Detached HEAD. Cannot rebase." }
    if (-not $AllowInProgress -and (Test-GitInProgress)) { throw "Another git operation is in progress." }
    if (-not $AllowDirty -and -not (Test-WorkingTreeClean)) { throw "Working tree is not clean." }
    if (-not $NoFetch) { git fetch --all --prune; if ($LASTEXITCODE -ne 0) { throw "git fetch failed." } }
    if ($Autostash) { git rebase --autostash $Src } else { git rebase $Src }
}

function gapt   { git apply --3way @args }
function gcor   { git checkout --recurse-submodules @args }
function gdct   { git describe --tags (git rev-list --tags --max-count=1) }
function gdt    { git diff-tree --no-commit-id --name-only -r @args }
function gdnolock { git diff @args ":(exclude)package-lock.json" ":(exclude)*.lock" }
function gdv    { git diff -w @args | Out-String | less }
function gfo    { git fetch origin @args }
function glp    { param([string]$format) if($format){ git log --pretty=$format } else { git log } }
function gmtl   { git mergetool --no-prompt @args }
function gmtlvim{ git mergetool --no-prompt --tool=vimdiff @args }
function gtv    { git tag | Sort-Object { $_ -as [version] } }
function gtl    { param($p='') git tag --sort=-v:refname -n -l "$p*" }
function gwip   { git add -A; git rm (git ls-files --deleted) 2>$null; git commit --no-verify --no-gpg-sign -m "--wip-- [skip ci]" }
function gunwip { if (git log -n 1 | Select-String -Quiet -- "--wip--") { git reset HEAD~1 } }

function grsh { git reset --soft HEAD~1 }
function gccd   {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$rest)
    git clone --recurse-submodules @rest
    $last = if ($rest.Count) { $rest[-1] } else { '' }
    if ($last -match '\.git$') { $last = $last -replace '\.git$','' }
    if ($last) {
      $dirName = Split-Path $last -Leaf
      if (Test-Path $dirName) {
        Set-Location $dirName
      }
    }
}
function grl    { git reflog @args }

# Get commit hash - returns the hash of HEAD or HEAD~n
# Usage: ghash [steps] [-Short]
#   ghash          - full hash of HEAD
#   ghash 3        - full hash of HEAD~3
#   ghash -Short   - short hash of HEAD
#   ghash 3 -Short - short hash of HEAD~3
function ghash {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [int]$StepsBack = 0,
        [Alias('s')]
        [switch]$Short
    )
    
    if (-not (Test-InGitRepo)) {
        Write-Error "Not a git repository." -ErrorAction Stop
        return
    }
    
    $ref = if ($StepsBack -eq 0) { "HEAD" } else { "HEAD~$StepsBack" }
    
    try {
        if ($Short) {
            $hash = git rev-parse --short $ref 2>$null
        } else {
            $hash = git rev-parse $ref 2>$null
        }
        
        if ($LASTEXITCODE -eq 0 -and $hash) {
            $hash.Trim()
        } else {
            Write-Error "Invalid reference: $ref" -ErrorAction Stop
        }
    } catch {
        Write-Error "Failed to get commit hash: $_" -ErrorAction Stop
    }
}

function gsw {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$rest
    )

    # Keep native behavior for advanced invocations (flags, start-points, etc.).
    if ($rest.Count -ne 1 -or $rest[0].StartsWith('-')) {
        git switch @rest
        return
    }

    if (-not (Test-InGitRepo)) {
        git switch @rest
        return
    }

    $target = $rest[0].Trim()
    if (-not $target) {
        git switch @rest
        return
    }

    # Prefer an existing local branch first.
    if (Test-GitRefExists "refs/heads/$target") {
        git switch $target
        return
    }

    # If only remote exists, create a tracking local branch explicitly.
    # This avoids ambiguous SHA/ref parsing for numeric names like "8695".
    $defaultRemote = git config --get checkout.defaultRemote 2>$null
    if (-not $defaultRemote) { $defaultRemote = 'origin' }
    if (Test-GitRefExists "refs/remotes/$defaultRemote/$target") {
        git switch --track "$defaultRemote/$target"
        return
    }

    git switch @rest
}

function gswc    { git switch -c @args }

# Alias for shorter command

# --- Set Aliases for Custom Functions ---
Set-Alias gum UpMerge
Set-Alias gur UpRebase
Set-Alias gh ghash


# ===================================================================
# Tab Completion Registration
# ===================================================================
function Register-GitAliasCompletion {
    # 1. Build a map of alias functions to their git subcommands
    $script:gitAliasMap = @{}
    $aliasRegex = '^\s*git\s+([\w-]+)\s+'

    # Get all aliases from the 'git-aliases' module
    Get-Command -Module git-aliases | ForEach-Object {
        $definition = (Get-Content Function:\$($_.Name)).ToString()
        if ($definition -match $aliasRegex) {
            $script:gitAliasMap[$_.Name] = $matches[1]
        }
    }

    # Add your custom aliases from this module
    Get-Command -Module GitAliases.Extras -CommandType Function | ForEach-Object {
        $func = $_
        $definition = $func.ScriptBlock.ToString()
        if ($definition -match $aliasRegex) {
            $subCommand = $matches[1]
            $script:gitAliasMap[$func.Name] = $subCommand
        }
    }

    # Manually add complex functions that don't fit the regex pattern
    $script:gitAliasMap['gum'] = 'merge'
    $script:gitAliasMap['gur'] = 'rebase'
    $script:gitAliasMap['gccd'] = 'clone'
    $script:gitAliasMap['gsw'] = 'switch'

    if ($script:gitAliasMap.Count -eq 0) {
        Write-Warning "No git alias functions were found to register for completion."
        return
    }

    # 2. Create the proxy completer script block
    $proxyCompleter = {
        param($wordToComplete, $commandAst, $cursorPosition)

        $commandName = $commandAst.CommandElements[0].Value
        $subCommand = $script:gitAliasMap[$commandName]

        # Reconstruct the command line as if 'git <subcommand>' was typed
        $line = $commandAst.Extent.Text
        $gitLine = $line -replace "^$commandName", "git $subCommand"
        $offset = ("git $subCommand").Length - $commandName.Length
        $gitCursorPosition = $cursorPosition + $offset

        # Use posh-git's official completion function
        if (Get-Command GitTabExpansion -ErrorAction SilentlyContinue) {
            try {
                return GitTabExpansion $gitLine $gitCursorPosition
            } catch {
                Write-Warning "posh-git's GitTabExpansion failed for alias '$commandName'."
            }
        }

        # Fallback if posh-git isn't loaded or its function fails
        if ($subCommand -in @('checkout', 'switch', 'merge', 'rebase', 'branch', 'reset', 'revert')) {
            try {
                $branches = git branch -a --format='%(refname:short)' |
                            ForEach-Object { $_ -replace '^remotes/origin/', '' } |
                            Sort-Object -Unique |
                            Where-Object { $_ -like "$wordToComplete*" }
                if ($branches) {
                    return $branches | ForEach-Object {
                        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                    }
                }
            } catch {}
        }

        # Return nothing if no completions are found
        return @()
    }

    # 3. Register the completer for every alias found
    foreach ($aliasName in $script:gitAliasMap.Keys) {
        # Ensure we only register for commands that actually exist
        if (Get-Command $aliasName -ErrorAction SilentlyContinue) {
            Register-ArgumentCompleter -CommandName $aliasName -ScriptBlock $proxyCompleter
        }
    }

    Write-Host "Git alias tab completion is now active for $($script:gitAliasMap.Count) aliases." -ForegroundColor Cyan
}

# --- Run Registration and Export Members ---

# This runs when the module is imported
Register-GitAliasCompletion

# Export all public functions and aliases for use in the shell
Export-ModuleMember -Function * -Alias *
