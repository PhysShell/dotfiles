# --- PSReadLine Configuration ---
# This enhances the command-line editing experience.
if (Get-Module -ListAvailable -Name PSReadLine) {
  if (-not (Get-Module -Name PSReadLine)) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
  }
  Set-PSReadLineOption -BellStyle None

  function Protect-HashBranchTokenForCompletion {
    [string]$line = ''
    [int]$cursor = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if (-not $line -or $cursor -le 0) { return $false }
    if ($cursor -gt $line.Length) { $cursor = $line.Length }

    $prefix = $line.Substring(0, $cursor)
    if ($prefix -notmatch '^\s*(?:git\s+switch|gsw)\b') { return $false }

    $tokenStart = $prefix.Length
    while ($tokenStart -gt 0 -and -not [char]::IsWhiteSpace($prefix[$tokenStart - 1])) {
      $tokenStart--
    }

    if ($tokenStart -ge $prefix.Length) { return $false }
    if ($prefix[$tokenStart] -ne '#') { return $false }

    [Microsoft.PowerShell.PSConsoleReadLine]::Replace($tokenStart, 1, '`#')
    return $true
  }

  # Use Tab for menu completion and Shift+Tab to go backward.
  # Workaround: in PowerShell, unescaped '#' starts a comment, so we
  # auto-escape it for git switch/gsw branch completion.
  Set-PSReadLineKeyHandler -Key Tab -ScriptBlock {
    try { Protect-HashBranchTokenForCompletion | Out-Null } catch { Write-Verbose $_ }
    [Microsoft.PowerShell.PSConsoleReadLine]::MenuComplete()
    try { Protect-HashBranchTokenForCompletion | Out-Null } catch { Write-Verbose $_ }
  }
  Set-PSReadLineKeyHandler -Key "Shift+Tab" -Function TabCompletePrevious
}

# --- Add your custom modules directory to the PSModulePath ---
# This ensures PowerShell can find your 'git-aliases-extra' module.
$dotFilesRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$dotModules = Join-Path $dotFilesRoot 'modules'
$sep = [IO.Path]::PathSeparator
if ($env:PSModulePath -notlike "*$dotModules*") {
  $env:PSModulePath = "$dotModules$sep$env:PSModulePath"
}

# --- Load Git Modules in the Correct Order ---
# 1. posh-git: Provides the core Git prompt and tab completion engine.
# It MUST be loaded first.
Import-Module posh-git -ErrorAction Stop

# 2. git-aliases: Provides the standard set of 'g' aliases (gco, gsw, etc.).
Import-Module git-aliases -ErrorAction Stop -DisableNameChecking

# Set the base 'g' alias to 'git' after modules that might define it as a function.
# This ensures 'g<tab>' works correctly.
if (Get-Command g -CommandType Function -ErrorAction SilentlyContinue) {
  Remove-Item Function:\g -Force -ErrorAction SilentlyContinue
}
Set-Alias -Name g -Value git -Force

# 3. git-aliases-extra: Your custom module that DEPENDS on posh-git.
# It finds all aliases and registers the proxy completer.
$extrasManifest = Join-Path $dotFilesRoot 'modules\git-aliases-extra\git-aliases-extra.psd1'
if (-not (Get-Module -Name git-aliases-extra -ErrorAction SilentlyContinue)) {
  if (Test-Path -LiteralPath $extrasManifest) {
    Import-Module $extrasManifest -DisableNameChecking -ErrorAction Stop
  } elseif (Test-Path -LiteralPath (Join-Path $dotFilesRoot '.gitmodules')) {
    Write-Warning "git-aliases-extra is missing. Initialize submodules: git -C '$dotFilesRoot' submodule update --init --recursive"
  } else {
    Write-Warning "git-aliases-extra module not found at '$extrasManifest'."
  }
}

# Write-Host "PowerShell profile loaded. Posh-git and custom alias completion are active." -ForegroundColor Green
