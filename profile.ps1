# Install-Module PSReadLine -Scope CurrentUser -Force
Import-Module PSReadLine
#Set-PSReadLineKeyHandler -Key Tab -Function Complete
Set-PSReadLineOption -BellStyle None
Set-PSReadLineKeyHandler -Key "Tab"       -Function MenuComplete
Set-PSReadLineKeyHandler -Key "Shift+Tab" -Function TabCompletePrevious


Import-Module posh-git

Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
