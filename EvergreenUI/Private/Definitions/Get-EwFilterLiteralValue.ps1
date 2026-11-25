Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EwFilterLiteralValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Expression,

        [Parameter(Mandatory)]
        [psobject]$Artifact
    )

    if ($Expression -is [System.Management.Automation.Language.ParenExpressionAst]) {
        return Get-EwFilterLiteralValue -Expression $Expression.Pipeline -Artifact $Artifact
    }

    if ($Expression -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
        $Expression -is [System.Management.Automation.Language.ConstantExpressionAst]) {
        return $Expression.Value
    }

    if ($Expression -is [System.Management.Automation.Language.VariableExpressionAst]) {
        switch -CaseSensitive ($Expression.VariablePath.UserPath) {
            '_' { return $Artifact }
            'PSItem' { return $Artifact }
            'true' { return $true }
            'false' { return $false }
            'null' { return $null }
            default { throw "Unsupported variable in Application.Filter: '$($Expression.Extent.Text)'." }
        }
    }

    if ($Expression -is [System.Management.Automation.Language.MemberExpressionAst]) {
        if ($Expression.Static -or
            $Expression.Expression -isnot [System.Management.Automation.Language.VariableExpressionAst] -or
            $Expression.Expression.VariablePath.UserPath -notin @('_', 'PSItem') -or
            $Expression.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
            throw 'Application.Filter may only read literal properties from $_.'
        }

        $propertyName = [string]$Expression.Member.Value
        if ($propertyName -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Unsupported property name in Application.Filter: '$propertyName'."
        }
        $property = $Artifact.PSObject.Properties[$propertyName]
        if ($null -eq $property) {
            return $null
        }
        return $property.Value
    }

    if ($Expression -is [System.Management.Automation.Language.UnaryExpressionAst]) {
        if ([string]$Expression.TokenKind -ine 'Not') {
            throw "Unsupported unary operator in Application.Filter: '$($Expression.Extent.Text)'."
        }
        return -not [bool](Get-EwFilterLiteralValue -Expression $Expression.Child -Artifact $Artifact)
    }

    if ($Expression -is [System.Management.Automation.Language.BinaryExpressionAst]) {
        $operator = [string]$Expression.Operator
        if ($operator -ieq 'And') {
            return [bool](Get-EwFilterLiteralValue -Expression $Expression.Left -Artifact $Artifact) -and
                [bool](Get-EwFilterLiteralValue -Expression $Expression.Right -Artifact $Artifact)
        }
        if ($operator -ieq 'Or') {
            return [bool](Get-EwFilterLiteralValue -Expression $Expression.Left -Artifact $Artifact) -or
                [bool](Get-EwFilterLiteralValue -Expression $Expression.Right -Artifact $Artifact)
        }

        $left = Get-EwFilterLiteralValue -Expression $Expression.Left -Artifact $Artifact
        $right = Get-EwFilterLiteralValue -Expression $Expression.Right -Artifact $Artifact
        switch ($operator.ToLowerInvariant()) {
            'ieq' { return $left -eq $right }
            'ceq' { return $left -ceq $right }
            'ine' { return $left -ne $right }
            'cne' { return $left -cne $right }
            'ilike' { return $left -like $right }
            'clike' { return $left -clike $right }
            'inotlike' { return $left -notlike $right }
            'cnotlike' { return $left -cnotlike $right }
            'imatch' { return $left -match $right }
            'cmatch' { return $left -cmatch $right }
            'inotmatch' { return $left -notmatch $right }
            'cnotmatch' { return $left -cnotmatch $right }
            default { throw "Unsupported operator in Application.Filter: '$($Expression.Extent.Text)'." }
        }
    }

    throw "Unsupported expression in Application.Filter: '$($Expression.Extent.Text)'."
}
