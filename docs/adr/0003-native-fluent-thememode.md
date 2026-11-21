# Fluent styling uses WPF's native ThemeMode

With PowerShell 7.6 on .NET 10, WPF provides a native Fluent theme through `ThemeMode`. v2 uses it as the base for light, dark, accent and Mica behaviour instead of hand-building Fluent resource dictionaries. A small custom dictionary covers only what the native theme lacks, such as the NavigationView-style sidebar and icon glyphs. This replaces v1's `Set-LightTheme`, `Set-DarkTheme` and most of the DWM title bar code.
