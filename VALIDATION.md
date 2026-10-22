# Version 0.86 validation — 2026-10-22

## Baseline and scope

Based on the released `Infineon-TPM-Firmware-Updater-v0.85-PORTABLE.zip`.
Baseline SHA-256:
`3aca373855c6b84a950d60f65898c9483311fc4efe09b8b83ad6a5070f45a1e9`.
Changes are normal restart behavior at BIOS steps, the corresponding warnings,
restart errors, version metadata, and explicit 0.85 workflow compatibility.

## Executed regression checks

REGRESSION-TESTS.ps1 loads the actual shipped function definitions and uses
simulated Windows/TPM/provider/process responses. A process recorder replaces
Start-Process in restart tests; real shutdown.exe is never launched.

56 cases / 179 assertions passed under official PowerShell 7.4.6 on Linux:

- All 44 inherited 0.85 replacement-TPM, BitLocker, native protocol, and
  original safety-gate tests passed.
- Disable, enable, and intermediate reboot actions each use exactly `/r /t 0`.
  No firmware-setup request or forced-close flag is sent.
- Each action warns to save unsaved documents and close programs before the
  recorded restart request. BIOS steps explain manual setup entry and give the
  correct disable/enable instruction. Requested-step timestamps are saved.
- Cancelling each action leaves the workflow bytes unchanged and requests no
  restart. Nonzero restart exit codes produce an error and a technical log;
  they never create firmware or reboot completion checkmarks.
- BitLocker ON still prevents the disable-TPM restart.
- A consistent 0.85 workflow with a same-boot pending intermediate reboot
  migrates to 0.86 while retaining its mandatory reboot.
- Rebooting without enabling the BIOS setting does not mark the workflow
  complete. Live enabled-TPM evidence is still required.

All packaged PowerShell scripts parsed successfully. The regenerated flat
SHA256SUMS.txt was checked with VERIFY-PORTABLE.ps1 and the runtime integrity,
executable, driver, and firmware verification functions. The final ZIP was
extracted into a differently named folder and independently verified.

Both compiled executables, TVicPort.sys, all 12 firmware BIN images, and vendor
license/readme files are byte-for-byte identical to 0.85. The BitLocker-check
function, flashing function, firmware routes, replacement-TPM logic, and native
process/authorization/result-validation logic were compared with that baseline.

## Windows evidence and limits

The user ran the exact unchanged 0.85 BitLocker function on Swedish Windows
(UI culture sv-SE), Windows PowerShell 5.1.26100.9711, on 2026-10-22. It returned
ReturnValue=0 and ProtectionStatus=0 for C:, successfully allowing the gate.
That is evidence for the OFF case of the function retained in this release.

0.86 itself was assembled outside Windows. The new normal-restart actions,
Windows elevation, BIOS setting changes, driver loading, and physical TPM
flashing were not executed on real Windows hardware here. Automated restart
checks validate arguments, warnings, cancellation, failures, and workflow state
using simulated process responses, not actual machine restarts.

## Optional maintainer checks

Normal users only extract the ZIP and run TPM-Updater.exe. No build or test
commands are needed. Maintainers may run, from the extracted folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\00-PowerShell-Syntax-Check.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\REGRESSION-TESTS.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\VERIFY-PORTABLE.ps1
```

Users should not edit scripts or regenerate release manifests themselves.
See CHANGELOG-V0.85.md for the previous release's detailed changes.


## Complete source repository validation

The complete source archive was assembled from the verified 0.831 SOURCE archive
and the released 0.86 portable workflow. All original Source files, firmware
images, vendor documents, driver and MSVC response/config files remain intact.

The source-layout workflow suite passed: 56 cases / 179 assertions. The original
authorization/routing/native-parser/progress/process-exit/flash-result suite
also passed after updating its obsolete automatic-BIOS-restart assertions.
The process-exit fixture ran a real harmless PowerShell child process on Linux.

The actual Publish-PortableRuntime, Write-PortableRuntimeManifest, and
Assert-PortableRuntimeComplete build functions were executed against a temporary
runtime using the existing 0.86 release executables as fixtures. Publication,
file-copy equality, build identity, firmware hashes, and generated manifest
verification passed. This verifies the packaging stage, not MSVC compilation.

The Windows compiler response-file inputs and linker objects were cross-checked,
all required Windows project includes were resolved, and all source scripts
parsed successfully. The native compilation/link stages themselves were not
executed in this Linux environment. A real Windows MSVC build remains required
to confirm compiler, linker, embedded-manifest and freshly built startup checks.
