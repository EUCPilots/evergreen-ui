# Fluent styling uses WPF's native ThemeMode

With PowerShell 7.6 on .NET 10, WPF provides a native Fluent theme through `ThemeMode`. Workbench uses it as the base for light, dark, accent and Mica behaviour instead of hand-building Fluent resource dictionaries. A small custom dictionary covers only what the native theme lacks, such as the NavigationView-style sidebar and icon glyphs.

The window retains standard Windows borders and caption buttons. A limited DWM
override matches the solid native caption to `ApplicationBackgroundBrush` and
its text to the themed foreground, returning both colours to Windows in high
contrast. Mica remains in the window body, not the solid caption. WPF owns the
backdrop policy; Workbench exposes it through a transparent window background
only when available and otherwise uses the opaque themed background.
