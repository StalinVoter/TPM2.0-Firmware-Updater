# V0.8 validation record

## V0.8 regression coverage

The source-package test gate also checks the V0.8 operator layer: complete
one- and two-hop workflow construction, Windows-visible versus BIOS-hidden TPM
classification, the native launcher source and embedded elevation linker flag,
the `/r /fw /t 0` UEFI action, and the deterministic success banner. Portable
verification requires `TPM-Updater.exe` in the flat manifest and verifies its
recorded SHA-256 independently from the direct TPM helper.

Workflow checkmarks are designed to be evidence-derived. The current TPM
firmware determines completed update rows; a stored pending-reboot target is
accepted only when the live firmware has reached it, and the reboot row is
completed only after the Windows boot identifier changes. The TPM endorsement
public-key SHA-256 is compared whenever the TPM is exposed to Windows.

The V0.8 helper and synthetic test fixtures use V0.8 identity/policy tags, and
`Convert-DirectInfoToState` matches that protocol exactly. The authorization
regression fixture explicitly rejects stale V9.3 tags.

The BIOS-setting gate requires a two-paragraph end-user message containing only
the blocking condition and the corrective BIOS/UEFI action. A regression check
rejects messages containing previous-version references, `platformAuth`,
`authPolicy`, TPM capability/return-code identifiers, or PolicyFile details.

The flash confirmation is normalized with `Trim()` and a case-insensitive
comparison. Regression assertions cover uppercase, lowercase, mixed case with
surrounding whitespace, an empty response, and a non-FLASH response.

The flash-result fixtures reproduce representative successful physical
first- and second-stage outputs in which progress percentages are separated by
bare carriage returns. They prove that V0.8 recognizes the final 100-percent
update and exact target version while retaining independent rejections for a
wrong target version, nonzero exit, stdout error code, and internal-log error.

The live-progress fixtures prove that the displayed percentage is the newest
valid value reported by Infineon, that the 0/50/100 progress-bar shapes are
exact, and that no percentage is invented before native output contains one.
A real child-process regression fixture emits bare-CR 0/50/100 values and exits;
the watcher must return exit code 0 and retain 100 percent. A source assertion
also rejects any blocking `WaitForExit()` call in the firmware-flash function.

Date: 2026-08-23

## Preserved payloads

- `Driver/TVicPort.sys` SHA-256:
  `9c9ab56c8bcf5ec958e7c2346f23a3027f69abdf8af923b591518eee64ad98ad`
- All 12 supported source-to-target firmware images are pinned by exact
  filename and SHA-256 in both `UpdaterCommon.ps1` and
  `VERIFY-PORTABLE.ps1`. Regression coverage requires every declared route to
  resolve to its corresponding image and hash.

The Windows TVicPort/TIS transport remains functionally identical to the proven
V8.1.3 implementation; only its diagnostic version label changed.

## Supplied successful-flash evidence

The supplied 5.62-to-5.67 record had process exit 0, exact target
`5.67.19690.2`, valid new firmware, 100% completion, the explicit Infineon
success message, and 319 FieldUpgrade transfer commands. V0.8 preserves that
transport and those update-specific success gates.

## Authorization tests

`Tests/Authorization-Gates.Tests.ps1` covers identity/state/policy parsing,
empty-platformAuth routing, reported default-platform-policy routing, legacy
`0x000001C4` capability rejection, exact `0x0000012F` authorization-error
decoding, payload-transfer evidence classification, PolicyOR calculation, and
rejection of disabled, unknown, unqueryable, unproven, or mismatched
authorization states. The Windows build runs these tests before provisioning
or compilation.

The legacy classification is based on target evidence from firmware
`5.0.1089.2`: transport success, a valid 10-byte TPM response, and return code
`0x000001C4` (`TPM_RC_VALUE` for capability parameter 1). V0.8 parses the TPM
header before requiring the longer success payload.

The supplied V9.3 target log further proves that StartAuthSession and
PolicyCommandCode succeeded but FieldUpgradeStartVendor returned raw TPM code
`0x0000012F` (`TPM_RC_AUTH_UNAVAILABLE`). No subsequent `TPM_FieldUpgrade`
payload command appears. V0.8 therefore blocks this state during preflight and
does not rely on an authorization attempt as a policy probe.

## Portable-output checks

The build publishes every required runtime payload directly into `dist`,
removes temporary smoke-test output, records the exact executable hash, creates
a flat SHA-256 manifest, and runs `VERIFY-PORTABLE.ps1`. The verifier requires
the executable, driver, all 12 firmware images, launchers, common runtime,
PowerShell syntax checker, verifier, and build identity; it also independently
checks the pinned driver hash and every pinned firmware-image hash.

The runtime resolves its location from `PSScriptRoot`; it contains no fixed
drive letter, parent directory, or dist-folder name.

The wrapper also repairs a stopped, stale `TVICPORT` absolute `ImagePath` after
verifying the service is a kernel driver and any existing image has the pinned
hash. A running registration with a missing image is deliberately rejected.

## Validation boundary

This V0.8 source archive was assembled and archive-validated outside the target
Windows 11 machine. Before `dist` exists, a real V0.8 MSVC build remains to be
performed on a Windows build computer. When the build explicitly reports
`Portable runtime ready`, its build, link, executable smoke test, publication,
and portable integrity verification have completed successfully. Merely finding
an incomplete `dist` left after a failed build is not success. A BIOS-enabled
physical TPM flash of V0.8 remains hardware validation. Build failures stop
before a portable dist is declared complete. The newly fail-closed legacy gate
must be confirmed on the target by observing that it refuses the BIOS-enabled
non-empty/unqueryable state and proceeds only after the live probe reports
Empty Buffer.
