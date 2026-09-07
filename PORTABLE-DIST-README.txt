IFX TPM Firmware Updater V0.8 PORTABLE
======================================

This file is copied into dist as README.txt.

Run
---

Start TPM-Updater.exe. It is the elevated V0.8 console application. Typing
TPM-Updater in Command Prompt selects the EXE before the compatibility CMD file.

The application silently detects the supported discrete Infineon TPM 2.0,
installed firmware, Windows/BIOS TPM exposure, exact available update route,
portable integrity, and saved workflow. The screen contains only the useful
firmware summary, checklist, current arrow, confirmations, exact native-derived
progress bar, and a concise result.

Press Enter to perform the arrowed step, Y to confirm, or Esc to exit.

For a BIOS step the application first says that the computer will reboot and
enter UEFI settings. It then uses Windows /r /fw so the next restart enters the
firmware interface. It does not force applications closed.

Workflow continuity
-------------------

State is stored at:

  C:\ProgramData\IFX-TPM-Updater-V0.8\Workflow.json

The workflow is bound to this package build and computer, and to the TPM
endorsement-key hash whenever Windows can read it. Checkmarks are revalidated
against the live firmware and boot identifier on every run. The saved file
alone can never prove that a firmware update happened.

Logs
----

Every run creates a new detailed run-*.txt in this folder's logs directory.
Direct TPM output, Windows TPM state, authorization and policy data, workflow
decisions, exact file paths, and failures go there instead of onto the normal
screen. Native Infineon and direct-transport logs are kept beside it.

Firmware update
---------------

Before a write, BitLocker protection must be suspended, Trusted Computing must
be disabled in BIOS/UEFI, and the direct TPM must report empty platformAuth.
The application then repeats the complete live safety check immediately before
starting the pinned BIN for the exact source version.

The 40-cell progress bar follows Infineon's own Completion percentage exactly.
It is not estimated. After the native process exits, V0.8 verifies exit code,
target version, firmware validity, 100 percent, explicit success text, and the
absence of errors. It then redraws the checklist immediately and marks the
mandatory reboot as the next action.

Portable folder
---------------

Copy, move, rename, or re-zip this complete folder as one unit. Do not copy
selected files. TPM-Updater.exe, TPMFactoryUpd-Direct-Win11-x64.exe,
TVicPort.sys, the 12 BIN files, scripts, documentation, BUILD-INFO.txt, and
SHA256SUMS.txt are all required.

VERIFY-PORTABLE.cmd performs a read-only integrity check without accessing the
TPM. The portable folder cannot rebuild itself; rebuild only from the complete
V0.8 source package with:

  TPM-Updater.cmd -Action Build
