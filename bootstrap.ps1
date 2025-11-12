function Ensure-Module($name, [Version]$min = $null) {
  $ok = Get-Module -ListAvailable $name | Where-Object { -not $min -or $_.Version -ge $min }
  if (-not $ok) { Install-Module $name -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck }
}

# PSReadLine is required for Windows PowerShell 5.1; it's already built into PowerShell Core (pwsh)
if ($PSVersionTable.PSEdition -ne 'Core') { Ensure-Module PSReadLine ([Version]'2.2.6') }

Ensure-Module posh-git
Ensure-Module git-aliases

Write-Host "Bootstrap done. Restart PowerShell."

