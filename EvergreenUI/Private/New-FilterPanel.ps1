#Requires -Version 5.1
<#
.SYNOPSIS
    Builds WPF filter controls at runtime and injects them into the filter WrapPanel.

.DESCRIPTION
    Accepts the output of Get-FilterableProperties and a reference to the parent
    WrapPanel in the UI. For each filterable property it creates the appropriate
    WPF control (CheckBox strip, multi-select ListBox, or TextBox), wires up
    change handlers that call Invoke-FilterUpdate, and appends the group to the
    WrapPanel.

    All WPF controls are instantiated directly as .NET objects (no XAML parsing
    at this stage) so the function can run on the UI thread without needing a
    separate XamlReader call.

    The $syncHash.FilterState hashtable is (re-)initialised by this function
    with all values selected by default for each property.

.PARAMETER FilterProperties
    Output from Get-FilterableProperties — array of property metadata objects.

.PARAMETER WrapPanel
    The System.Windows.Controls.WrapPanel that hosts the filter groups.

.PARAMETER SyncHash
    Shared synchronised hashtable. FilterState key is written here.

.PARAMETER OnChangeCallback
    A scriptblock to invoke whenever a filter control value changes.
    Typically: { Invoke-FilterUpdate -SyncHash $syncHash }

.NOTES
    TODO: Implement WPF control construction in Phase 4.
#>
function New-FilterPanel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [PSObject[]]$FilterProperties,

        [Parameter(Mandatory)]
        [System.Windows.Controls.WrapPanel]$WrapPanel,

        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$SyncHash,

        [Parameter(Mandatory)]
        [scriptblock]$OnChangeCallback
    )

    # Clear existing controls and reset filter state
    $WrapPanel.Children.Clear()
    $SyncHash.FilterState = @{}

    if ($FilterProperties.Count -eq 0) {
        # TODO: show "No filterable properties" TextBlock
        return
    }

    foreach ($prop in $FilterProperties) {
        # Initialise filter state — all values selected
        $SyncHash.FilterState[$prop.Name] = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]$prop.UniqueValues,
            [System.StringComparer]::OrdinalIgnoreCase
        )

        # TODO: Build StackPanel group with label + control per $prop.ControlType
        # Phase 4 implementation:
        #   'CheckBoxStrip' → StackPanel of CheckBox per unique value
        #   'MultiListBox'  → ListBox with SelectionMode=Multiple
        #   'TextBox'       → TextBox with TextChanged handler (contains-match)
    }
}
