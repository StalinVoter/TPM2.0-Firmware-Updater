# V0.8 PORTABLE changes

## V0.8 fixes

- Corrected a Windows PowerShell 5.1 incompatibility in the new route and
  checklist collections. Generic `List[T]` values are converted with
  `ToArray()` instead of being passed directly through `@()`, which previously
  caused `Argument types do not match` during the pre-build route tests.

- Replaced the normal verbose PowerShell status screen with a focused,
  color-coded checklist. Completed items are green with a check mark; the
  currently actionable item has an arrow and is executed with Enter plus Y
  confirmation.
- Added a separately compiled `TPM-Updater.exe` console application with an
  embedded `requireAdministrator` manifest. It owns elevation and launches the
  internal PowerShell workflow from the portable folder in the same console.
- Added silent, bounded Windows TPM exposure detection alongside the proven
  direct physical probe. The interface distinguishes Windows/BIOS-enabled TPM
  operation from a TPM hidden by disabled Trusted Computing.
- Added UEFI workflow actions using `shutdown.exe /r /fw /t 0`, preceded by an
  explicit warning that the computer will reboot and enter UEFI settings.
- Added `Workflow.json` continuity under ProgramData, bound to the computer,
  exact pinned route, package build, boot identifier, and TPM endorsement-key
  hash when Windows exposes it. Firmware checkmarks are reconstructed from the
  live version rather than trusted from the saved file.
- Added a new detailed `run-*.txt` for every execution. Direct and Windows TPM
  probe results, workflow state, and failures are logged while normal console
  output remains concise.
- Preserved the exact Infineon-derived progress bar and deterministic result
  classifier, then redraws the checklist immediately after success so the
  application cannot appear stuck after the native process has finished.

- Corrected all five direct-info parser expressions to consume the current
  `[V0.8 IDENTITY]` and `[V0.8 POLICY]` helper tags. The broken V9.8
  package retained escaped `V9\.7` expressions and therefore failed its first
  positive synthetic identity test before compilation.
- Added explicit regression assertions that require the current escaped parser
  tag and reject the stale escaped V9.7 tag.
- Expanded exact firmware routing from two images to 12 images. V0.8 now
  supports all source versions represented by the supplied Infineon image set,
  including the newly supplied direct `5.63.3144.0 -> 5.67.19690.2` route.
- Pinned every image by its exact SHA-256 and made the source version, target
  version, filename, and hash one indivisible route. V0.8 never tries an image
  whose declared source does not exactly match the detected TPM firmware.
- Updated source and portable-runtime completeness checks so all 12 firmware
  images must be present and protected by `SHA256SUMS.txt`.
- Added a live 40-cell console progress bar whose numeric percentage is taken
  exclusively from Infineon's native `Completion: N %` output. The wrapper
  does not estimate time, bytes, packets, or completion.
- Replaced the firmware-write `WaitForExit()` call with explicit process-state
  polling. The wrapper reads progress while the process is alive, performs a
  final capture read after process exit, validates the result, and immediately
  prints the completed/reboot message.
- Stopped copying the multi-megabyte Infineon command trace into the summary
  log. The trace remains intact in its own named log, while the summary records
  that path. This removes unnecessary post-flash file processing.
- Restricted line-oriented result regexes to horizontal whitespace so they
  cannot consume newline sequences while scanning the captured logs.
- Added regression coverage for bare-CR progress extraction, exact progress-bar
  formatting, final 100-percent capture, and prompt return after a real child
  process exits.
- Replaced the legacy-BIOS authorization failure's developer-facing explanation
  with a concise instruction to disable TPM 2.0 / Security Device Support in
  BIOS/UEFI and rerun the updater. Previous updater versions and internal TPM
  policy identifiers are no longer shown in this end-user error message.
- Added a regression assertion that requires the exact actionable message and
  rejects historical version references or internal policy terminology.
- Fixed the V9.4 post-flash false failure. Infineon's updater redraws progress
  percentages with bare carriage returns, so `Completion: 100 %` did not begin
  a conventional newline-delimited line. V0.8 normalizes console line endings
  before evaluating the completion evidence.
- Added a physical-flash regression fixture matching the captured successful
  `5.0.1089.2 -> 5.62.3126.2` and `5.62.3126.2 -> 5.67.19690.2` outputs. The
  classifier still requires exit code zero, valid new firmware, the exact target
  version, 100-percent completion, the explicit Infineon success message, and
  no stdout or internal-log error.

- Fixed the confirmation prompt so `FLASH` is accepted case-insensitively and
  with surrounding whitespace. Inputs other than `FLASH` now print
  `Update cancelled.` instead of silently exiting.
- Carries forward the helper protocol fix: the V0.8 C helper and
  authorization fixtures emit `[V0.8 IDENTITY]` and `[V0.8 POLICY]`, and the
  PowerShell parser now consumes those exact V0.8 tags instead of stale V9.3
  tags.
- Added a regression assertion that accepts V0.8 helper output and rejects
  stale V9.3 helper tags.

V0.8 preserves the authorization correction exposed by target testing of V9.3
and the portable-service correction introduced in V9.3.

- A stopped `TVICPORT` service whose absolute `ImagePath` refers to an earlier
  folder is safely relocated to the pinned `TVicPort.sys` beside the running
  V0.8 launcher. The service must be a kernel-driver service; an existing
  on-disk driver must match the pinned hash. A running service whose original
  image is missing remains fail-closed because its loaded image cannot be
  authenticated.
- Moving, renaming, or changing the drive letter of the complete `dist` folder
  no longer requires manually deleting the stopped `TVICPORT` service.
- The platform-policy probe now parses valid 10-byte TPM error responses before
  applying success-response length checks.
- TPM return code `0x000001C4` is classified precisely: legacy firmware rejects
  the `TPM_CAP_AUTH_POLICIES` selector rather than suffering a transport error.
- With non-empty `platformAuth` and that exact legacy result, V0.8 is
  fail-closed. It does not offer `FLASH`, accept a PolicyFile, or issue
  `TPM2_FieldUpgradeStartVendor` because the live authPolicy cannot be proven.
- The V9.3 target response `0x0000012F` is decoded as
  `TPM_RC_AUTH_UNAVAILABLE`, not hidden behind Infineon's generic
  `0xE029550A` message.
- Actual payload transfer is recognized only from `TPM_FieldUpgrade` commands;
  Infineon's earlier `Updating the TPM firmware ...` banner is not treated as
  transfer evidence.
- A supplied PolicyOR file is still structurally checked, must include the
  FieldUpgrade command-code digest, and is compared exactly with the live
  policy whenever the firmware supports reporting that policy.
- Unknown and unsupported policy-query states remain fail-closed.
- V9.2's flat, self-contained build output, manifests, pinned payloads,
  firmware routing, live revalidation, and no-force-kill write behavior remain.
