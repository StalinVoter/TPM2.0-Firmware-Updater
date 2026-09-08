IFX TPM Firmware Updater V0.831 PORTABLE
=======================================

WHAT THIS APPLICATION DOES
--------------------------

This application updates supported discrete Infineon TPM 2.0 modules to the
newest firmware included in this package: 5.67.19690.2.

It is not for Intel PTT, AMD fTPM, TPM 1.2 devices, or TPMs made by another
manufacturer. The updater checks the TPM and stops without flashing if the
device or its current firmware is not supported.

BEFORE YOU BEGIN
----------------

1. Save your work and close other programs.
2. Make sure you know your Windows account password.
3. Save your BitLocker recovery key if BitLocker or Device Encryption is used.
4. Suspend BitLocker protection on the Windows drive:
   - Open Start and search for Manage BitLocker.
   - Open it, select Suspend protection for drive C:, and confirm.

Do not clear, reset, erase, or physically remove the TPM. When the application
asks you to disable Trusted Computing, change only the BIOS/UEFI setting that
enables or disables the TPM.

HOW TO START
------------

Keep every file in this folder together. Double-click TPM-Updater.exe and
select Yes when Windows asks for administrator permission.

The application displays the installed firmware and a checklist:

  Enter = perform the step marked by the arrow
  Y     = confirm the selected step
  Esc   = exit without performing the step

Run TPM-Updater.exe again after every restart. It remembers completed steps
and checks them against the TPM before continuing.

STEP-BY-STEP UPDATE
-------------------

1. DISABLE TRUSTED COMPUTING

   When the arrow points to the BIOS/UEFI step, press Enter and then Y. The
   computer will restart and try to open BIOS/UEFI settings automatically.

   Find Trusted Computing, Security Device Support, or TPM Device and disable
   it. Save the setting and let Windows start. Do not select Clear TPM, Reset
   TPM, or Erase TPM.

2. RUN THE APPLICATION AGAIN

   Open this folder and start TPM-Updater.exe again. The arrow should now point
   to the firmware update.

3. INSTALL THE FIRMWARE UPDATE

   Press Enter and then Y. Do not restart, shut down, or disconnect power while
   the progress bar is moving. Wait for the successful-completion message.

4. RESTART WHEN REQUESTED

   Press Enter and then Y when the checklist points to Reboot. After Windows
   starts, run TPM-Updater.exe again. Some older TPM versions require a second
   firmware update; follow the next arrow if one is shown.

5. RE-ENABLE TRUSTED COMPUTING

   After the final firmware update, follow the arrowed BIOS/UEFI step. Re-enable
   the same Trusted Computing, Security Device Support, or TPM Device setting.
   Save the setting and let Windows start.

   Run TPM-Updater.exe once more. It should report that the firmware is current
   and the checklist is complete.

6. RESUME BITLOCKER

   Return to Manage BitLocker and select Resume protection if protection is
   still suspended.

IF SOMETHING GOES WRONG
-----------------------

- If Windows cannot open BIOS/UEFI automatically, restart manually and press
  the motherboard's setup key during startup. Delete and F2 are common keys.
- If the application reports an unsupported TPM or firmware version, do not
  substitute another BIN file and do not try to force the update.
- If the application stops with an error, open the logs folder beside it. Send
  the newest run-*.txt file when asking for help.
- Move or copy this complete folder as one unit. Do not move or delete selected
  files inside it.
