Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-EwDefinitionFilter {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Filter
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $Filter,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0 -or $ast.EndBlock.Statements.Count -ne 1) {
        throw 'Application.Filter is not a supported Evergreen query.'
    }

    $pipeline = $ast.EndBlock.Statements[0]
    if ($pipeline -isnot [System.Management.Automation.Language.PipelineAst]) {
        throw 'Application.Filter must be a pipeline query.'
    }

    $elements = @($pipeline.PipelineElements)
    if ($elements.Count -lt 1 -or $elements.Count -gt 3) {
        throw 'Application.Filter supports one source command, an optional Where-Object predicate, and an optional Select-Object -First 1.'
    }

    $sourceCommand = $elements[0]
    if ($sourceCommand -isnot [System.Management.Automation.Language.CommandAst]) {
        throw 'Application.Filter must start with Get-EvergreenApp or Get-VcList.'
    }

    $sourceElements = @($sourceCommand.CommandElements)
    if ($sourceElements[0] -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
        throw 'Application.Filter has an unsupported source command.'
    }

    $commandName = [string]$sourceElements[0].Value
    $appName = ''
    if ($commandName -ieq 'Get-EvergreenApp') {
        if ($sourceElements.Count -ne 3 -or
            $sourceElements[1] -isnot [System.Management.Automation.Language.CommandParameterAst] -or
            [string]$sourceElements[1].ParameterName -ine 'Name' -or
            $sourceElements[2] -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
            throw 'Get-EvergreenApp must use a literal -Name value.'
        }
        $appName = [string]$sourceElements[2].Value
    }
    elseif ($commandName -ieq 'Get-VcList') {
        if ($sourceElements.Count -ne 1) {
            throw 'Get-VcList does not accept additional arguments in Application.Filter.'
        }
    }
    else {
        throw "Unsupported Application.Filter source command '$commandName'."
    }

    $predicate = $null
    $hasSelect = $false
    for ($index = 1; $index -lt $elements.Count; $index++) {
        $command = $elements[$index]
        if ($command -isnot [System.Management.Automation.Language.CommandAst]) {
            throw 'Application.Filter contains an unsupported pipeline element.'
        }

        $commandParts = @($command.CommandElements)
        if ($commandParts[0] -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
            throw 'Application.Filter contains an unsupported command.'
        }

        $downstreamName = [string]$commandParts[0].Value
        if ($downstreamName -ieq 'Where-Object' -and $null -eq $predicate) {
            if ($commandParts.Count -ne 2 -or
                $commandParts[1] -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                throw 'Where-Object must contain one supported literal predicate.'
            }

            $statements = @($commandParts[1].ScriptBlock.EndBlock.Statements)
            if ($statements.Count -ne 1 -or
                $statements[0] -isnot [System.Management.Automation.Language.PipelineAst] -or
                $statements[0].PipelineElements.Count -ne 1 -or
                $statements[0].PipelineElements[0] -isnot [System.Management.Automation.Language.CommandExpressionAst]) {
                throw 'Where-Object must contain one supported literal predicate.'
            }
            $predicate = $statements[0].PipelineElements[0].Expression
            [void](Get-EwFilterLiteralValue -Expression $predicate -Artifact ([PSCustomObject]@{}))
        }
        elseif ($downstreamName -ieq 'Select-Object' -and -not $hasSelect) {
            if ($commandParts.Count -ne 3 -or
                $commandParts[1] -isnot [System.Management.Automation.Language.CommandParameterAst] -or
                [string]$commandParts[1].ParameterName -ine 'First' -or
                $commandParts[2] -isnot [System.Management.Automation.Language.ConstantExpressionAst] -or
                [int]$commandParts[2].Value -ne 1) {
                throw 'Select-Object only supports -First 1 in Application.Filter.'
            }
            $hasSelect = $true
        }
        else {
            throw "Unsupported Application.Filter command '$downstreamName'."
        }
    }

    [PSCustomObject]@{
        CommandName = $commandName
        AppName     = $appName
        Predicate   = $predicate
        Filter      = $Filter
    }
}
