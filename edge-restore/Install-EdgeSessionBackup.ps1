param(
    [int]$IntervalMinutes = 10,
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
$taskName = 'EdgeSessionBackup'

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    return
}

$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = (Get-Command powershell).Source }
$script = Join-Path $PSScriptRoot 'Backup-EdgeSessions.ps1'

# conhost --headless keeps the console window from flashing on every run
$action = New-ScheduledTaskAction -Execute 'conhost.exe' `
    -Argument "--headless `"$pwsh`" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script`""
$triggers = @(
    New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Settings $settings `
    -Description 'Snapshots the Edge session file so tabs can be restored after a crash' -Force | Out-Null
Write-Host "Task '$taskName' registered: every $IntervalMinutes min -> $script"
