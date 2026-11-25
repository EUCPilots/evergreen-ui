# The UI is a thin layer over a public headless cmdlet layer

Public `*-Ew*` cmdlets provide Workbench functionality without WPF, making
the behavior testable and usable independently of the UI. The UI calls those
cmdlets, and the headless layer is built and verified before UI work starts.
Background work goes through one Job abstraction (a `RunspacePool` with
progress, log and cancellation events).
