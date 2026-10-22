# Version 0.85 — 2026-10-04

This is a ready-to-run portable revision of the supplied 0.831 package.
No compiler, build tools, or user edits to scripts/manifests are required.

## Replacement TPM and saved workflow

- Detect incompatible saved progress before applying it to the live TPM.
  An older live firmware version after the recorded reboot is treated as an
  opportunity to start a fresh session, including when the computer fingerprint
  is unchanged and the TPM endorsement key is unavailable while hidden from Windows.
- Display “Start a new update for the connected TPM” with Enter/Y confirmation.
  Show a clean checklist built from the connected TPM's live firmware.
- Archive the original workflow bytes before saving the fresh record. Copy no
  completed targets, reboot markers, BIOS action markers, or old TPM identity.
  Declining the action leaves the previous record unchanged.
- Resume consistent 0.831 sessions explicitly. A real same-boot pending reboot
  remains mandatory, including if the new firmware is exposed only after restart.
- Store current workflow state in `%ProgramData%\IFX-TPM-Updater-V0.85`.
  If no current workflow exists, inspect the existing 0.831 workflow automatically.
  Archived records are kept in the current state folder's `Archives` subfolder.

## BitLocker

- Replace English `manage-bde -status` text parsing with
  `Win32_EncryptableVolume.GetProtectionStatus()` through CIM.
- Query only the Windows system drive, obtained from `$env:SystemDrive`.
- Require numeric ReturnValue=0 and ProtectionStatus=0. ON, UNKNOWN, provider
  failures, missing/invalid fields, and unexpected statuses block maintenance.
  No fallback to localized command output is used.
- Keep the original safety gates before the UEFI-disable action and firmware flash.
- Log the queried drive, provider, raw returned values, decision, and technical
  failure reason. Give protection-ON errors a clear instruction to suspend it.

## Package and validation

- Retain both compiled executables, TVicPort.sys, all 12 BIN images, and vendor
  licenses/readme unchanged from the supplied 0.831 portable package.
- Preserve the native helper's `[V0.831 IDENTITY]` / `[V0.831 POLICY]` protocol;
  its binaries were not rebuilt or relabeled. Version 0.85 applies to this wrapper
  and portable release.
- Include a self-contained regression script and regenerate SHA256SUMS.txt.
- Exclude the supplied historical run logs from the release.
- See VALIDATION.md for checks performed and their limits.
