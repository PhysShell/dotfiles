# dotfiles

To install put following content in $PROFILE.CurrentUserAllHosts:

```powershell
# Microsoft.PowerShell_profile.ps1 (CurrentUserAllHosts)
$dot = Join-Path $HOME 'dotfiles\profile.ps1'
if (Test-Path $dot) { . $dot }```
