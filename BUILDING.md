# Building version 0.86

## Build on Windows 11 x64

Extract this complete source ZIP or clone the repository. Keep the directory
structure, including Source, Driver, Firmware, Tests, and the root build files.
You do not need an older package or a previous checkout alongside it.

From the repository root, run:

```bat
TPM-Updater.cmd -Action Build
```

Accept the administrator prompt. The wrapper runs its syntax check and starts
the build path before TPM detection; building does not require a discrete TPM.
The build validates the bundled driver and runs both the authorization tests
and the 56-case workflow/BitLocker/restart suite before provisioning/compilation.

The inherited build script detects suitable Visual Studio Build Tools and the
Windows SDK. When they are missing, it uses Microsoft's signed Build Tools
bootstrapper and the included vsconfig files. Internet access is needed when
prerequisites must be downloaded. Follow any prerequisite restart instruction
and run the same build command again afterward.

The script compiles the native helper using build-msvc.rsp, links it using
link-msvc.rsp, and separately compiles/links the console launcher with an
embedded requireAdministrator manifest. It verifies the launcher manifest,
checks the helper's -help startup output, publishes the flat runtime to dist,
records executable hashes in BUILD-INFO.txt, regenerates the runtime
SHA256SUMS.txt, and runs VERIFY-PORTABLE.ps1.

Only a completed build reporting “Portable runtime ready” establishes that the
Windows build and startup checks succeeded. Then copy the entire dist folder,
or ZIP its contents for the release. Run dist\TPM-Updater.exe to use the updater.
Build diagnostics are written in logs beside the source scripts.

## Tests without compiling

On Windows PowerShell, from the source root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\00-PowerShell-Syntax-Check.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\Authorization-Gates.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\REGRESSION-TESTS.ps1
```

The authorization suite starts a harmless PowerShell child process to check
progress capture and process exit. Neither suite accesses a TPM or flashes
firmware. The workflow suite simulates restart commands instead of rebooting.
On non-Windows PowerShell, set ProgramData to a temporary directory for the
authorization suite; the workflow suite supplies and restores its own environment.

To test publication separately, supply an extracted 0.86 portable release or
a successfully built 0.86 dist directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\Portable-Publication.Tests.ps1 -ReferenceRuntime "C:\path\to\TPM-updater-v0.86"
```

This runs the actual publication/manifest/verifier functions in a temporary
folder using those existing executable fixtures. It does not compile or run
the native TPM helper. It removes its temporary folder afterward.

## Source and runtime manifests

The root SHA256SUMS.txt inventories this source snapshot using relative paths.
The build generates a separate flat manifest in dist. VERIFY-PORTABLE.ps1 is
for the built dist directory, not the source root. Source checkouts preserve
file bytes so PowerShell UTF-8 BOMs and the source snapshot hashes survive Git
checkout. Build outputs and logs are excluded from source tracking.

## Build reproducibility limits

All project source and Windows build inputs are included. The vendor driver
and firmware are supplied binaries. A new MSVC build may produce different EXE
hashes because toolchain versions, timestamps, and environment can differ; the
build records and verifies the newly produced hashes. This source package was
not compiled using Windows MSVC in the Linux packaging environment.
