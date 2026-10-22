# Version 0.86 — 2026-10-22

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
- Both executables, driver, all 12 firmware images, and native helper protocol
  remain unchanged. No native rebuild or user-side build is required.

## Validation

56 regression cases / 179 assertions passed with simulated Windows/TPM/restart
responses. Syntax, manifest, pinned payload, and portable extraction checks were
also performed. No actual restart, firmware-setting change, or TPM flash was
performed here. See VALIDATION.md for the test scope.
