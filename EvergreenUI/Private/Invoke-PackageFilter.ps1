#Requires -Version 5.1

function ConvertFrom-PackageFilterLiteral {
    [CmdletBinding()]
    [OutputType([object], [object[]])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ExpressionAst]$Expression
    )

    if ($Expression -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
        $Expression -is [System.Management.Automation.Language.ConstantExpressionAst]) {
        return $Expression.Value
    }

    if ($Expression -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        return @($Expression.Elements | ForEach-Object {
                ConvertFrom-PackageFilterLiteral -Expression $_
            })
    }

    throw "Only literal argument values are supported. Got: $($Expression.Extent.Text)"
}

function ConvertTo-PackageFilterParameter {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.CommandAst]$Command,

        [Parameter(Mandatory)]
        [string[]]$AllowedParameter,

        [Parameter()]
        [string[]]$SwitchParameter = @()
    )

    $parameters = @{}
    $elements = @($Command.CommandElements)

    for ($index = 1; $index -lt $elements.Count; $index++) {
        $element = $elements[$index]
        if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) {
            throw "Positional arguments are not supported in '$($Command.GetCommandName())'."
        }

        $parameterName = [string]$element.ParameterName
        $canonicalName = @($AllowedParameter | Where-Object { $_ -ieq $parameterName } | Select-Object -First 1)
        if ($canonicalName.Count -eq 0) {
            throw "Parameter '-$parameterName' is not supported for '$($Command.GetCommandName())'."
        }

        $parameterName = $canonicalName[0]
        if ($parameters.ContainsKey($parameterName)) {
            throw "Parameter '-$parameterName' may only be specified once."
        }

        if ($null -ne $element.Argument) {
            $parameters[$parameterName] = ConvertFrom-PackageFilterLiteral -Expression $element.Argument
            continue
        }

        $isSwitch = $SwitchParameter -icontains $parameterName
        if ($isSwitch) {
            $parameters[$parameterName] = $true
            continue
        }

        $index++
        if ($index -ge $elements.Count -or
            $elements[$index] -is [System.Management.Automation.Language.CommandParameterAst] -or
            $elements[$index] -isnot [System.Management.Automation.Language.ExpressionAst]) {
            throw "Parameter '-$parameterName' requires a literal value."
        }

        $parameters[$parameterName] = ConvertFrom-PackageFilterLiteral -Expression $elements[$index]
    }

    return $parameters
}

function ConvertTo-PackageFilterPredicate {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ExpressionAst]$Expression
    )

    if ($Expression -is [System.Management.Automation.Language.ParenExpressionAst]) {
        $pipeline = $Expression.Pipeline
        if ($pipeline.PipelineElements.Count -ne 1 -or
            $pipeline.PipelineElements[0] -isnot [System.Management.Automation.Language.CommandExpressionAst]) {
            throw 'Parenthesized predicates must contain a single property comparison.'
        }

        return ConvertTo-PackageFilterPredicate -Expression $pipeline.PipelineElements[0].Expression
    }

    if ($Expression -isnot [System.Management.Automation.Language.BinaryExpressionAst]) {
        throw "Only property comparison predicates are supported. Got: $($Expression.Extent.Text)"
    }

    if ($Expression.Operator -in @(
            [System.Management.Automation.Language.TokenKind]::And,
            [System.Management.Automation.Language.TokenKind]::Or
        )) {
        return [PSCustomObject]@{
            Kind     = 'Logical'
            Operator = [string]$Expression.Operator
            Left     = ConvertTo-PackageFilterPredicate -Expression $Expression.Left
            Right    = ConvertTo-PackageFilterPredicate -Expression $Expression.Right
        }
    }

    $allowedOperators = @(
        [System.Management.Automation.Language.TokenKind]::Ieq,
        [System.Management.Automation.Language.TokenKind]::Ine,
        [System.Management.Automation.Language.TokenKind]::Ilike,
        [System.Management.Automation.Language.TokenKind]::Inotlike,
        [System.Management.Automation.Language.TokenKind]::Imatch,
        [System.Management.Automation.Language.TokenKind]::Inotmatch,
        [System.Management.Automation.Language.TokenKind]::Igt,
        [System.Management.Automation.Language.TokenKind]::Ige,
        [System.Management.Automation.Language.TokenKind]::Ilt,
        [System.Management.Automation.Language.TokenKind]::Ile,
        [System.Management.Automation.Language.TokenKind]::Icontains,
        [System.Management.Automation.Language.TokenKind]::Inotcontains,
        [System.Management.Automation.Language.TokenKind]::Iin,
        [System.Management.Automation.Language.TokenKind]::Inotin
    )
    if ($Expression.Operator -notin $allowedOperators) {
        throw "Predicate operator '$($Expression.Operator)' is not supported."
    }

    $member = $Expression.Left
    if ($member -isnot [System.Management.Automation.Language.MemberExpressionAst] -or
        $member.Static -or
        $member.Expression -isnot [System.Management.Automation.Language.VariableExpressionAst] -or
        $member.Expression.VariablePath.UserPath -ne '_' -or
        $member.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
        throw 'The left side of a predicate must be a direct property reference such as $_.Architecture.'
    }

    return [PSCustomObject]@{
        Kind     = 'Comparison'
        Property = [string]$member.Member.Value
        Operator = [string]$Expression.Operator
        Value    = ConvertFrom-PackageFilterLiteral -Expression $Expression.Right
    }
}

function Test-PackageFilterPredicate {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Predicate,

        [Parameter()]
        [AllowNull()]
        [object]$InputObject
    )

    if ($Predicate.Kind -eq 'Logical') {
        $leftResult = Test-PackageFilterPredicate -Predicate $Predicate.Left -InputObject $InputObject
        if ($Predicate.Operator -eq 'And') {
            return ($leftResult -and (Test-PackageFilterPredicate -Predicate $Predicate.Right -InputObject $InputObject))
        }

        return ($leftResult -or (Test-PackageFilterPredicate -Predicate $Predicate.Right -InputObject $InputObject))
    }

    $property = $InputObject.PSObject.Properties[$Predicate.Property]
    if ($null -eq $property) {
        return $false
    }

    $actual = $property.Value
    $expected = $Predicate.Value
    switch ($Predicate.Operator) {
        'Ieq' { return $actual -eq $expected }
        'Ine' { return $actual -ne $expected }
        'Ilike' { return $actual -like $expected }
        'Inotlike' { return $actual -notlike $expected }
        'Imatch' { return $actual -match $expected }
        'Inotmatch' { return $actual -notmatch $expected }
        'Igt' { return $actual -gt $expected }
        'Ige' { return $actual -ge $expected }
        'Ilt' { return $actual -lt $expected }
        'Ile' { return $actual -le $expected }
        'Icontains' { return $actual -contains $expected }
        'Inotcontains' { return $actual -notcontains $expected }
        'Iin' { return $actual -in $expected }
        'Inotin' { return $actual -notin $expected }
        default { throw "Predicate operator '$($Predicate.Operator)' is not supported." }
    }
}

function Invoke-PackageFilter {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilterExpression
    )

    $fail = {
        param([string]$Msg)
        return [PSCustomObject]@{
            Succeeded        = $false
            Results          = @()
            FilterExpression = $FilterExpression
            Error            = $Msg
        }
    }

    try {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            $FilterExpression,
            [ref]$tokens,
            [ref]$parseErrors
        )

        if ($parseErrors.Count -gt 0) {
            throw "Filter syntax is invalid: $($parseErrors[0].Message)"
        }

        if ($ast.EndBlock.Statements.Count -ne 1 -or
            $ast.EndBlock.Statements[0] -isnot [System.Management.Automation.Language.PipelineAst]) {
            throw 'The filter must contain exactly one pipeline. Command separators and chained statements are not supported.'
        }

        $pipeline = $ast.EndBlock.Statements[0]
        if ($pipeline.PipelineElements.Count -eq 0) {
            throw 'The filter pipeline is empty.'
        }

        $commands = @($pipeline.PipelineElements)
        if (@($commands | Where-Object { $_ -isnot [System.Management.Automation.Language.CommandAst] }).Count -gt 0) {
            throw 'Only direct commands are supported in the filter pipeline.'
        }

        foreach ($command in $commands) {
            if ($command.InvocationOperator -ne [System.Management.Automation.Language.TokenKind]::Unknown) {
                throw 'Invocation operators and dot-sourcing are not supported.'
            }
            if ($command.Redirections.Count -gt 0) {
                throw 'Redirection is not supported.'
            }
        }

        $sourceCommand = $commands[0]
        $sourceName = $sourceCommand.GetCommandName()
        if ($sourceName -notin @('Get-EvergreenApp', 'Get-VcList')) {
            throw "Unsupported source command '$sourceName'. Only Get-EvergreenApp and Get-VcList are supported."
        }

        $allowedSourceParameter = if ($sourceName -eq 'Get-EvergreenApp') {
            @('Name', 'ErrorAction', 'WarningAction')
        }
        else {
            @('Release', 'Architecture', 'ErrorAction', 'WarningAction')
        }
        $sourceParameters = ConvertTo-PackageFilterParameter `
            -Command $sourceCommand `
            -AllowedParameter $allowedSourceParameter

        if ($sourceParameters.ContainsKey('ErrorAction')) {
            $errorAction = [string]$sourceParameters.ErrorAction
            if ($errorAction -notin @('Stop', 'Continue', 'SilentlyContinue', 'Ignore')) {
                throw "ErrorAction '$errorAction' is not supported. Use Stop, Continue, SilentlyContinue, or Ignore."
            }
            $sourceParameters.ErrorAction = $errorAction
        }
        else {
            $sourceParameters.ErrorAction = 'Stop'
        }

        if ($sourceParameters.ContainsKey('WarningAction')) {
            $warningAction = [string]$sourceParameters.WarningAction
            if ($warningAction -notin @('Stop', 'Continue', 'SilentlyContinue', 'Ignore')) {
                throw "WarningAction '$warningAction' is not supported. Use Stop, Continue, SilentlyContinue, or Ignore."
            }
            $sourceParameters.WarningAction = $warningAction
        }

        $operations = [System.Collections.Generic.List[object]]::new()
        foreach ($command in @($commands | Select-Object -Skip 1)) {
            $commandName = $command.GetCommandName()
            switch ($commandName) {
                'Where-Object' {
                    if ($command.CommandElements.Count -ne 2 -or
                        $command.CommandElements[1] -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                        throw 'Where-Object must contain one predicate script block.'
                    }

                    $predicateBlock = $command.CommandElements[1].ScriptBlock
                    if ($null -eq $predicateBlock.EndBlock -or
                        $predicateBlock.EndBlock.Statements.Count -ne 1 -or
                        $predicateBlock.EndBlock.Statements[0] -isnot [System.Management.Automation.Language.PipelineAst]) {
                        throw 'Where-Object must contain one property comparison predicate.'
                    }

                    $predicatePipeline = $predicateBlock.EndBlock.Statements[0]
                    if ($predicatePipeline.PipelineElements.Count -ne 1 -or
                        $predicatePipeline.PipelineElements[0] -isnot [System.Management.Automation.Language.CommandExpressionAst]) {
                        throw 'Where-Object must contain one property comparison predicate.'
                    }

                    $operations.Add([PSCustomObject]@{
                            Name      = 'Where-Object'
                            Predicate = ConvertTo-PackageFilterPredicate -Expression $predicatePipeline.PipelineElements[0].Expression
                        })
                }
                'Sort-Object' {
                    $parameters = ConvertTo-PackageFilterParameter `
                        -Command $command `
                        -AllowedParameter @('Property', 'Descending', 'Unique') `
                        -SwitchParameter @('Descending', 'Unique')
                    if (-not $parameters.ContainsKey('Property')) {
                        throw 'Sort-Object requires a literal -Property value.'
                    }
                    $operations.Add([PSCustomObject]@{ Name = 'Sort-Object'; Parameters = $parameters })
                }
                'Select-Object' {
                    $parameters = ConvertTo-PackageFilterParameter `
                        -Command $command `
                        -AllowedParameter @('Property', 'ExcludeProperty', 'ExpandProperty', 'First', 'Last', 'Skip', 'Unique') `
                        -SwitchParameter @('Unique')
                    $operations.Add([PSCustomObject]@{ Name = 'Select-Object'; Parameters = $parameters })
                }
                default {
                    throw "Pipeline command '$commandName' is not supported."
                }
            }
        }

        if ($sourceName -eq 'Get-EvergreenApp') {
            $results = @(Get-EvergreenApp @sourceParameters)
        }
        else {
            $results = @(Get-VcList @sourceParameters)
        }

        foreach ($operation in $operations) {
            switch ($operation.Name) {
                'Where-Object' {
                    $predicate = $operation.Predicate
                    $results = @($results | Where-Object {
                            Test-PackageFilterPredicate -Predicate $predicate -InputObject $_
                        })
                }
                'Sort-Object' {
                    $parameters = $operation.Parameters
                    $results = @($results | Sort-Object @parameters)
                }
                'Select-Object' {
                    $parameters = $operation.Parameters
                    $results = @($results | Select-Object @parameters)
                }
            }
        }

        return [PSCustomObject]@{
            Succeeded        = $true
            Results          = @($results)
            FilterExpression = $FilterExpression
            Error            = ''
        }
    }
    catch {
        return (& $fail "Package filter rejected or failed: $($_.Exception.Message)")
    }
}