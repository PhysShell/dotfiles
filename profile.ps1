# --- PSReadLine Configuration ---
# This enhances the command-line editing experience.
Import-Module PSReadLine -ErrorAction SilentlyContinue
Set-PSReadLineOption -BellStyle None
# Use Tab for menu completion and Shift+Tab to go backward.
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineKeyHandler -Key "Shift+Tab" -Function TabCompletePrevious

# --- Add your custom modules directory to the PSModulePath ---
# This ensures PowerShell can find your 'GitAliases.Extras' module.
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
Import-Module git-aliases -ErrorAction Stop

# Set the base 'g' alias to 'git' after modules that might define it as a function.
# This ensures 'g<tab>' works correctly.
if (Get-Command g -CommandType Function -ErrorAction SilentlyContinue) {
  Remove-Item Function:\g -Force -ErrorAction SilentlyContinue
}
Set-Alias -Name g -Value git -Force

# 3. GitAliases.Extras: Your custom module that DEPENDS on posh-git.
# It finds all aliases and registers the proxy completer.
Import-Module GitAliases.Extras -Force -ErrorAction Stop

Write-Host "PowerShell profile loaded. Posh-git and custom alias completion are active." -ForegroundColor Green