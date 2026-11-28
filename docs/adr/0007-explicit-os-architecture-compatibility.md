# Use explicit OS architecture requirements for installation and Intune

A Definition's `RequirementRule.Architecture` identifies compatible OS architectures, while `Application.Architecture` selects an Artifact variant. Both local installation and Intune publishing use the same exact OS allowlist instead of inferring vendor support from Windows emulation. This permits an x64 Artifact to exclude ARM64 even when the OS can emulate x64.

Local installation requires explicit approval for missing requirements, x64 on ARM64, and unknown Artifact architecture on ARM64. Invalid or excluded architectures are blocked. Intune publishing requires a valid explicit requirement and does not prompt each target device. Detection remains an independent observation of installed state.

Architecture labels do not establish that every installer component, driver, or installed application supports a target. Windows 11 ARM64 supports x86 and x64 emulation, subject to [Microsoft's documented limits](https://learn.microsoft.com/en-us/windows/arm/apps-on-arm-x86-emulation). Windows 10 is outside the solution's supported scope.
