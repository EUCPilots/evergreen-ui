# Local installation uses an emulation-aware architecture check

Local installation interprets a Definition's architecture requirement using
the local OS execution matrix rather than Intune's OS-target mapping. This
allows x86 applications on x64 and Arm64, while requiring explicit approval
for x64 on Arm64; Intune targeting remains unchanged. The distinction permits
local installation without silently broadening Intune assignments.

A missing requirement also needs approval, while invalid requirements and
known-incompatible Artifacts are blocked. Users can approve x64 on Windows 10
Arm64 despite [Windows 10's lack of x64 emulation](https://learn.microsoft.com/windows/arm/apps-on-arm-x86-emulation);
the warning makes that limitation explicit. Architecture metadata does not
guarantee that an application or its drivers will run.
