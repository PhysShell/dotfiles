param(
    [string]$SessionFile,
    [switch]$List
)
$ErrorActionPreference = 'Stop'
$live = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Sessions"
$backups = "$env:LOCALAPPDATA\EdgeSessionBackups"

if (-not $SessionFile) {
    $candidates = @(Get-ChildItem $live -Filter 'Session_*' -File -ErrorAction SilentlyContinue)
    if (Test-Path $backups -PathType Container) {
        $candidates += @(Get-ChildItem $backups -Recurse -Filter 'Session_*' -File)
    }
    $edgeStart = Get-Process msedge -ErrorAction SilentlyContinue | Sort-Object StartTime | Select-Object -First 1 -ExpandProperty StartTime
    if (-not $edgeStart) { $edgeStart = Get-Date }
    $SessionFile = $candidates | Where-Object { $_.Length -gt 0 -and $_.LastWriteTime -lt $edgeStart } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $SessionFile) { throw 'No session file found' }

$py = Join-Path $PSScriptRoot 'snss.py'
$json = python -I -X utf8 $py $SessionFile
$windows = $json | ConvertFrom-Json
Write-Host "Session: $SessionFile ($((Get-Item $SessionFile).LastWriteTime))"
$i = 0
foreach ($w in $windows) {
    $i++
    Write-Host "Window ${i}: $(@($w).Count) tabs"
    if ($List) { $w | ForEach-Object { Write-Host "   $($_.url)" }; continue }
    $urls = @($w | ForEach-Object url | Where-Object { $_ -and $_ -notmatch '^(edge|chrome)://newtab' })
    if (-not $urls) { continue }
    Start-Process msedge -ArgumentList (@('--new-window') + ($urls | ForEach-Object { '"' + $_ + '"' }))
    Start-Sleep -Milliseconds 1500
}
