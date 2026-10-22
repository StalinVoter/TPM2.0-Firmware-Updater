# Version 0.86 — 2026-10-22

## BitLocker language fix retained from 0.85

- The old updater could refuse to continue even when BitLocker protection was
  correctly suspended, simply because Windows used Swedish or another language.
- It looked for the exact English words "Protection Status: Protection Off".
  On non-English Windows, the same status appeared in another language, so the
  updater failed to recognize it and stopped.
- The fixed version asks Windows for a status number whose meaning stays the
  same in every language. It can recognize that protection is off without
  relying on English wording. Your Swedish Windows test confirmed this works.
- It checks only the Windows system drive. BitLocker protection on an unrelated
  D: or E: drive no longer causes this check to stop the update.
- The safety check remains: protection that is on, an unknown state, or a failed
  status check still prevents TPM maintenance.

## Normal restart at BIOS steps

- Replace automatic firmware-setup restart requests with a normal Windows
  restart at BOTH disable- and enable-Trusted-Computing steps.
- Both now use `shutdown.exe /r /t 0`, without `/fw` or forced-close `/f`.
- Before confirmation, tell the user to save all unsaved documents and close
  programs, then explain the ordinary restart and manual BIOS/UEFI setup key.
- Tell the user exactly which Trusted Computing setting to disable or enable,
  then to save the BIOS setting and let Windows boot.
- Cancellation starts no restart and changes no saved workflow.
- Preserve native exit-code logging and report ordinary restart failures clearly.
- Keep the intermediate reboot as a normal restart with a save-work warning.

## Continuity

- Retain 0.85's replacement-TPM recovery and its exact numeric system-drive
  BitLocker function. Both BitLocker gate call sites remain in place.
- Accept consistent 0.85 workflows and keep the existing state directory
  `%ProgramData%\IFX-TPM-Updater-V0.85`; a pending reboot is not discarded
  just because this wrapper was upgraded. The 0.831 fallback is retained.
- A restart request does not prove the user changed a BIOS setting. Live TPM
  checks still determine the next action and final completion.
- The fixes are in the included PowerShell scripts. Both existing EXE files,
  the driver, and all 12 firmware images remain unchanged. Extract the complete
  ZIP and run TPM-Updater.exe; no compiling or build tools are required.

## Validation

56 regression cases / 179 assertions passed with simulated Windows/TPM/restart
responses. Syntax, manifest, pinned payload, and portable extraction checks were
also performed. No actual restart, firmware-setting change, or TPM flash was
performed here. See VALIDATION.md for the test scope.
