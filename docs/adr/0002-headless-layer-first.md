# The UI is a thin layer over a public headless cmdlet layer

v1 kept almost all logic inside a 438 KB `Start-EvergreenWorkbench` and its event handlers, which made it hard to test or troubleshoot. In v2 all functionality is exposed as public `*-Ew*` cmdlets that work without WPF, the UI calls only those cmdlets, and the headless layer is built and verified before any UI work starts. Background work goes through one Job abstraction (a `RunspacePool` with progress, log and cancellation events) that both the cmdlets and the UI use.
