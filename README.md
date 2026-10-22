# Infineon TPM 2.0 Firmware Updater

This Windows 11 application updates the firmware on supported **discrete Infineon TPM 2.0 modules**. A discrete TPM is a small physical module installed on the motherboard.

The updater detects the TPM, reads its current firmware version, and shows a checklist containing only the steps required for that computer. It remembers completed steps between restarts and stops safely if the TPM or firmware is not supported.

The newest firmware included in version 0.86 of this updater is **5.67.19690.2**. Some older TPMs require two firmware updates, with a restart between them.

> This tool is not for Intel PTT, AMD fTPM, TPM 1.2 devices, or TPMs made by another manufacturer. If your TPM is not supported, the updater will say so and will not start a firmware update.

## Version 0.86 source repository

This repository includes the complete Windows updater project: the native C
helper and console launcher, PowerShell workflow, build/provisioning scripts,
compiler/linker response files, tests, 12 firmware images, and the supplied
TVicPort driver. The current PowerShell runtime files match the 0.86 portable
release. Build output is generated in `dist`; it is not stored in the source
root. No older checkout or obsolete folder is required.

The latest changes are normal restart requests with save-work warnings and
manual BIOS instructions. The replacement-TPM recovery and numeric system-drive
BitLocker check from 0.85 are retained. See [CHANGELOG-V0.86.md](CHANGELOG-V0.86.md).

## Before you begin

You need:

- Windows 11 64-bit
- a supported discrete Infineon TPM 2.0 module
- an administrator account
- your Windows account password and BitLocker recovery key, if BitLocker or Device Encryption is used

Save your work and close other programs before starting. The process requires several restarts.

Do **not** clear, reset, or remove the TPM. When the instructions say to disable Trusted Computing, only change the BIOS/UEFI setting that enables or disables the TPM.

### Suspend BitLocker first

Changing TPM settings can trigger a BitLocker recovery prompt. Suspend BitLocker protection before continuing:

1. Open the Start menu and search for **Manage BitLocker**.
2. Open **Manage BitLocker**.
3. Find the Windows drive, normally **C:**.
4. Select **Suspend protection**, then confirm.

If BitLocker is already off, no change is required. If the updater later reports that BitLocker protection is on, suspend it again before continuing.

## Download and start the updater

1. Open the [Releases](https://github.com/StalinVoter/TPM2.0-Firmware-Updater/releases) page.
2. Download the ready-to-use **V0.86 portable ZIP** from the release assets. Do not download the automatically generated “Source code” archives unless you intend to build the program yourself.
3. Right-click the downloaded ZIP and select **Extract All**.
4. Open the extracted folder. Keep every included file together in that folder.
5. Double-click **TPM-Updater.exe**.
6. Select **Yes** if Windows asks whether the program may make changes to the computer.

The initial check may take a little while. The application is detecting the TPM and choosing the correct update path.

## Follow the checklist

The updater displays your current firmware version and a checklist. Completed steps are green and have a check mark. An arrow points to the next available step.

- Press **Enter** to select the arrowed step.
- Press **Y** to confirm it.
- Press **Esc** if you want to exit without performing the step.

Only perform the step marked with the arrow. Run the same program again after every restart; it will remember your progress.

### 1. Disable Trusted Computing in BIOS/UEFI

When this is the arrowed step, press **Enter**, read the warning, save any open work, and press **Y**. The computer will restart normally. During startup, use your motherboard's setup key (commonly **Delete** or **F2**) to enter BIOS/UEFI manually.

In BIOS/UEFI, find the setting named **Trusted Computing**, **Security Device Support**, or **TPM Device**, and disable it. The exact name and location depend on the motherboard. Save the changes and exit BIOS/UEFI so Windows starts again.

Do not select an option named **Clear TPM**, **Reset TPM**, or **Erase TPM**.

### 2. Run the updater again

After Windows starts, open the same extracted folder and run **TPM-Updater.exe** again.

The previous step should now be green. The arrow should point to the firmware update.

### 3. Install the firmware update

Press **Enter**, then press **Y** to confirm the exact firmware versions shown on screen.

Do not shut down, restart, or disconnect power while the progress bar is moving. Wait until the application reports that the firmware update completed successfully.

### 4. Restart if requested

If the checklist points to **Reboot**, press **Enter** and then **Y**. After Windows starts, run **TPM-Updater.exe** again.

Some older firmware versions require a second update. If another update appears, repeat the firmware-update step and wait for it to finish.

### 5. Re-enable Trusted Computing

After the final firmware update, the arrow will point to **Reboot and enable Trusted Computing in BIOS/UEFI**.

Press **Enter**, save unsaved documents and close programs, then press **Y**. The computer restarts normally; press your motherboard's setup key during startup to enter BIOS/UEFI manually. In BIOS/UEFI, re-enable the same **Trusted Computing**, **Security Device Support**, or **TPM Device** setting that you disabled earlier. Save the changes and allow Windows to start.

Run **TPM-Updater.exe** once more. The updater should report that the firmware is up to date and that everything is complete.

Finally, return to **Manage BitLocker** and select **Resume protection** if protection is still suspended.

## If something goes wrong

The updater will stop before writing firmware if it cannot verify that the update is safe for the detected TPM.

- If it says BitLocker protection must be suspended, follow the BitLocker steps above and try again.
- Enter BIOS/UEFI manually during the normal restart using your motherboard’s setup key. Common keys are **Delete** and **F2**.
- If it says the TPM or firmware is unsupported, do not substitute another firmware file and do not attempt to force the update.
- If an error occurs, open the **logs** folder beside the updater. A new detailed text log is created every time the application runs. Attach the newest log when asking for help.

Do not move or delete individual files inside the portable folder. Move or copy the complete folder as one unit.

## Building from source

Most users should download the ready-to-use portable ZIP from the Releases page. To build the application yourself on Windows 11 x64, download or clone this repository and run:

```text
TPM-Updater.cmd -Action Build
```

When the build finishes, the ready-to-use application is in the newly created **dist** folder.


See [BUILDING.md](BUILDING.md) for the complete build and test instructions,
[PROVENANCE.md](PROVENANCE.md) for the source/payload origins, and
[VALIDATION.md](VALIDATION.md) for checks performed and their limits.

## Repository layout

| Path | Contents |
| --- | --- |
| `Source/Common`, `Source/TPMFactoryUpd` | Native helper C source and headers |
| `Source/Launcher/TPM-Updater-Launcher.c` | Elevated console-launcher source |
| `TPM-Updater.ps1`, `UpdaterCommon.ps1` | Current 0.86 workflow and safety checks |
| `Build-Windows11-x64.ps1` | Build Tools provisioning, compilation, linking and publication |
| `build-msvc.rsp`, `link-msvc.rsp` | Complete native compiler/linker input lists |
| `Firmware` | All 12 pinned BIN images and vendor documentation/license |
| `Driver/TVicPort.sys` | Supplied vendor driver binary |
| `Tests`, `REGRESSION-TESTS.ps1` | Authorization, workflow and publication tests |

The native helper intentionally retains its `[V0.831 IDENTITY]` and
`[V0.831 POLICY]` diagnostic tags. Those form its existing output protocol;
0.86 is the application/repository version. The matching parser is included.

Vendor firmware and the driver are distributed as the supplied binary payloads.
Their internal source code is not part of this project. Preserve the Infineon
source copyright/license notices and included firmware license when redistributing.
