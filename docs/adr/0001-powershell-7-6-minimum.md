# EvergreenUI v2 requires PowerShell 7.6 or later

v1 supported Windows PowerShell 5.1 and PowerShell 7. v2 drops 5.1 and targets PowerShell 7.6+ (.NET 10) only. This allows modern syntax such as `ForEach-Object -Parallel` and WPF's native Fluent theme support (`ThemeMode`), and removes the cost of dual-runtime compatibility. Users on older runtimes stay on the v1 module.
