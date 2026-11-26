param([int]$Keep = 48)
$ErrorActionPreference = 'Stop'
$live = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Sessions"
$root = "$env:LOCALAPPDATA\EdgeSessionBackups"

$src = Get-ChildItem $live -Filter 'Session_*' -File | Where-Object Length -gt 0 |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $src) { return }

New-Item -ItemType Directory -Force $root | Out-Null
$last = Get-ChildItem $root -Directory | Sort-Object Name -Descending | Select-Object -First 1
if ($last) {
    $prev = Get-ChildItem $last.FullName -File | Select-Object -First 1
    if ($prev -and $prev.Name -eq $src.Name -and $prev.Length -eq $src.Length) { return }
}

$dst = Join-Path $root (Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory $dst | Out-Null
$in = [IO.File]::Open($src.FullName, 'Open', 'Read', 'ReadWrite, Delete')
try {
    $out = [IO.File]::Create((Join-Path $dst $src.Name))
    try { $in.CopyTo($out) } finally { $out.Dispose() }
} finally { $in.Dispose() }
(Get-Item (Join-Path $dst $src.Name)).LastWriteTime = $src.LastWriteTime

Get-ChildItem $root -Directory | Sort-Object Name -Descending | Select-Object -Skip $Keep |
    Remove-Item -Recurse -Force
