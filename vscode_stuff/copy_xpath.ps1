# Example in VSCode tasks.json (you can use either pwsh.exe or powershell.exe depending on your preference and setup)
# {
#   "label": "XML: Copy absolute element path",
#   "type": "process",
#   "command": "C:\\Program Files\\PowerShell\\7\\pwsh.exe",
#   "args": [
#     "-NoProfile",
#     "-NonInteractive",
#     "-File",
#     "your\\path\\to\\copy_xpath.ps1",
#     "-File",
#     "${file}",
#     "-Line",
#     "${lineNumber}",
#     "-Column",
#     "${columnNumber}"
#   ],
#   "problemMatcher": [],
#   "presentation": {
#     "reveal": "never",
#     "panel": "shared"
#   }
# }

# Example in VSCode keybindings.json
# {
#     "key": "ctrl+alt+x",
#     "command": "workbench.action.tasks.runTask",
#     "args": "XML: Copy absolute element path",
#     "when": "editorTextFocus"
# }

param(
    [Parameter(Mandatory = $true)]
    [string]$File,

    [Parameter(Mandatory = $true)]
    [int]$Line,

    [Parameter(Mandatory = $true)]
    [int]$Column,

    [switch]$IncludeIndexes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Compare-Position {
    param(
        [int]$LineA,
        [int]$ColA,
        [int]$LineB,
        [int]$ColB
    )

    if ($LineA -lt $LineB) { return -1 }
    if ($LineA -gt $LineB) { return 1 }
    if ($ColA -lt $ColB) { return -1 }
    if ($ColA -gt $ColB) { return 1 }
    return 0
}

function Get-SiblingIndex {
    param(
        [System.Collections.ArrayList]$Stack,
        [string]$Name
    )

    if ($Stack.Count -eq 0) {
        return 1
    }

    $parent = $Stack[$Stack.Count - 1]
    if (-not $parent.ContainsKey('ChildCounters')) {
        $parent['ChildCounters'] = @{}
    }

    if (-not $parent['ChildCounters'].ContainsKey($Name)) {
        $parent['ChildCounters'][$Name] = 0
    }

    $parent['ChildCounters'][$Name]++
    return [int]$parent['ChildCounters'][$Name]
}

if (-not (Test-Path -LiteralPath $File)) {
    throw ("File not found: {0}" -f $File)
}

$settings = [System.Xml.XmlReaderSettings]::new()
$settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
$settings.IgnoreComments = $false
$settings.IgnoreProcessingInstructions = $false
$settings.IgnoreWhitespace = $false

$stack = [System.Collections.ArrayList]::new()
$bestPath = $null

$reader = [System.Xml.XmlReader]::Create($File, $settings)

try {
    while ($reader.Read()) {
        $lineInfo = [System.Xml.IXmlLineInfo]$reader
        $nodeLine = if ($lineInfo.HasLineInfo()) { $lineInfo.LineNumber } else { 0 }
        $nodeCol = if ($lineInfo.HasLineInfo()) { $lineInfo.LinePosition } else { 0 }

        $cmp = Compare-Position -LineA $nodeLine -ColA $nodeCol -LineB $Line -ColB $Column

        switch ($reader.NodeType) {
            ([System.Xml.XmlNodeType]::Element) {
                if ($cmp -gt 0) {
                    break
                }

                $index = Get-SiblingIndex -Stack $stack -Name $reader.Name

                $entry = @{
                    Name          = $reader.Name
                    Index         = $index
                    StartLine     = $nodeLine
                    StartColumn   = $nodeCol
                    ChildCounters = @{}
                }

                [void]$stack.Add($entry)

                $bestPath = @($stack | ForEach-Object { $_ })

                if ($reader.IsEmptyElement) {
                    [void]$stack.RemoveAt($stack.Count - 1)
                }
            }

            ([System.Xml.XmlNodeType]::EndElement) {
                if ($cmp -gt 0) {
                    break
                }

                if ($stack.Count -gt 0) {
                    [void]$stack.RemoveAt($stack.Count - 1)
                }

                $bestPath = @($stack | ForEach-Object { $_ })
            }

            default {
                if ($cmp -gt 0) {
                    break
                }

                $bestPath = @($stack | ForEach-Object { $_ })
            }
        }
    }
}
finally {
    $reader.Dispose()
}

if (-not $bestPath -or $bestPath.Count -eq 0) {
    throw ("Could not determine XML element for cursor position {0}:{1}" -f $Line, $Column)
}

$parts = foreach ($item in $bestPath) {
    if ($IncludeIndexes) {
        '{0}[{1}]' -f $item.Name, $item.Index
    }
    else {
        $item.Name
    }
}

$result = $parts -join '->'

try {
    Set-Clipboard -Value $result
}
catch {
    Write-Warning ("Could not copy to clipboard automatically: {0}" -f $_.Exception.Message)
}

Write-Output $result