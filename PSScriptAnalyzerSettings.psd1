@{
    Severity = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseApprovedVerbs',
        'PSUseSingularNouns',
        'PSUseConsistentWhitespace',
        'PSUseConsistentIndentation'
    )
    Rules = @{
        PSUseConsistentWhitespace = @{
            Enable = $true
        }
        PSUseConsistentIndentation = @{
            Enable = $true
            IndentationSize = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
        }
        PSAvoidUsingCmdletAliases = @{
            Enable = $true
            Whitelist = @()
        }
    }
}
