# NinjaGet - [PowerShell](https://microsoft.com/powershell) for NinjaOne to handle 3rd party patching using [WinGet](https://learn.microsoft.com/en-us/windows/package-manager/winget/)

In depth and step-by-step documentation is coming very very soon - until then you need this entire source tree on the endpoints (we use `ProgramData\NinjaGet`) and all your usage will revolve around the `NinjaGetEntryPoint.ps1` file.

## Setup

After putting the files in place some setup tasks need to take place - these are handled by the `Setup` operation which is invoked with:

```ps
.\NinjaGetEntryPoint.ps1 -Operation Setup
```

See [the source](https://github.com/homotechsual/ninjaget/blob/dev/NinjaGetEntryPoint.ps1)
