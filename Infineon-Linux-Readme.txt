--------------------------------------------------------------------------------
                       Infineon TPM Firmware Update Tools
                           (Package with Tools Only)
                               For Use with Linux
                            Infineon Technologies AG
                                 v02.03.4733.00
                           Release Notes (2025-02-06)

All information in this document is
Copyright 2014 - 2025 Infineon Technologies AG ( www.infineon.com ).
All rights reserved.
Redistribution of this file is only permitted in connection with the
distribution of Infineon TPM Firmware Update Tools (Package with Tools Only).

Ubuntu is a registered trademark of Canonical Ltd.
Raspberry Pi is a registered trademark of Raspberry Pi Foundation
Linux is a registered trademark of Linus Torvalds
--------------------------------------------------------------------------------

Contents:

1. Welcome
1.1 Prerequisites
1.2 Contents of the Package
1.3 Firmware Images

2. Compilation

3. Usage of TPMFactoryUpd

4. If You Have Questions

5. Release Info
5.1 About This Release
5.2 New Features, Fixes, and Improvements
5.3 Known Bugs and Limitations
5.4 Further Information

================================================================================

1. Welcome

Welcome to Infineon TPM Firmware Update Tools.

The package contains the following tool:

- TPMFactoryUpd is a Linux command line application that enables a
  manufacturing/service facility to update the firmware of an Infineon TPM
  (Trusted Platform Module).

For further information about TPM and TCG (Trusted Computing Group) please visit
https://www.trustedcomputinggroup.org


1.1 Prerequisites

- Supported platforms
    * Linux 64-bit on x64 platforms
    * Linux 32-bit and 64-bit on ARM platforms, little endian

- Tested Linux distributions
    * Ubuntu Linux 24.04 LTS (64-bit, kernel version 6.8) on x64 platforms
    * Raspberry Pi OS Bookworm (32-bit and 64-bit, kernel version  6.6) on
      Raspberry Pi 5 and Raspberry Pi 4

- Tested compilers
    * gcc 12
    * gcc 13

- Rights to run the software
      Read/write access to /dev/tpm0
    or
      Root / su


1.1.1 Supported Devices

- Infineon TPM SLB 9670 TPM2.0
- Infineon TPM SLB 9670 TPM1.2
- Infineon TPM SLB 9672 TPM2.0
- Infineon TPM SLB 9673 TPM2.0 (requires Linux kernel >= 6.1)


1.1.2 Important Hints

To avoid any interruption of the update process, it is necessary to suspend all
usage of the TPM during the update process.

Do not turn off or shut down the system during the update process.

In case TPM Firmware Update process has been interrupted, please follow the
steps in chapter "Further Information".

It is recommended to always restart the system directly after the TPM Firmware
Update, since certain system hardware and software components might not be aware
of a TPM Firmware Update without a restart (especially in case the TPM family
has been changed with the update).

The total number of firmware updates allowed by the TPM is limited (please
consult your local Infineon representative for further details). Once the limit
has been reached, no further TPM Firmware Update will be possible.
This is also true if the counter for updates onto the same firmware version
becomes zero, even if the overall update counter would allow further updates.
The counter for updates onto the same firmware is decremented if a firmware
update was interrupted or firmware recovery was performed (only SLB 9672 and
SLB 9673).

Please note that TPM Firmware Update between TPM1.2 and TPM2.0 families resets
the TPM to factory defaults. For further details about TPM factory defaults
please refer to TPMFactoryUpd User Manual.


1.2 Contents of the Package

File name                             Description
=========                             ===========
Doc/TPMFactoryUpdLinuxDoc.tar.gz      Infineon TPM Factory Update Tool Linux
                                      source code documentation

Doc/TPMFactoryUpd_UserManual.pdf      Infineon TPM Factory Update Tool User's
                                      Manual

Source/**/*.*                         Linux source code for TPMFactoryUpd

Readme.txt                            This file

License.txt                           Legal disclaimer


1.3 Firmware Images

TPM firmware images are not part of this package.


2. Compilation

The OpenSSL package libssl-dev must be installed (LTS version 1.1.1 or 3.0).

$ sudo apt update
$ sudo apt install libssl-dev

Unzip the package and change to the directory Source/TPMFactoryUpd.

$ cd Source/TPMFactoryUpd

Call "make" to compile TPMFactoryUpd. After calling "make" an executable named
"TPMFactoryUpd" will be created in the current directory.

$ make

Run TPMFactoryUpd with root rights

$ sudo ./TPMFactoryUpd


3. Usage of TPMFactoryUpd

Please refer to the Infineon TPM Factory Update Tool User's Manual.


4. If You Have Questions

If you have any questions or problems, please see chapter "Release Info"
for further instructions or contact your local Infineon representative.
Further information is available at https://www.infineon.com/tpm


5. Release Info

5.1 About This Release

TPMFactoryUpd Source code release version is 02.03.4733.00.


5.2 New Features, Fixes, and Improvements

[N]ew Features, [R]emoved Features, [F]ixes, and [I]mprovements.

Changes with package version 02.03.4733.00
- [I] Add additional optional check of the TPM sales code against the TPM vendor
      string to prevent incorrect update paths.

Changes with package version 02.03.4566.00
- [F] Fix stuck in TPM update mode 0x03/0x83 (only SLB9672).
- [F] Clear TPM continue session flag for TPM2_FieldUpgradeStartVendor command
      so that TPM resource management correctly marks the utilized session as
      finished.
- [F] Fix unexpected error/termination of tool if reading UTF-16-LE encoded
      config file.

Changes with package version 02.03.3900.00 (since version 02.01.3534.00)
- [N] Add support for SLB 9673.
- [N] Add support for OpenSSL 3.0.
- [N] Add support for firmware update use cases with already set TPM2.0
      platform policy (not having empty platform authorization).

Changes since package version 01.04.2811.00
- [N] Add support for SLB 9672.
- [N] Command line option to switch into firmware update or recovery mode.
- [N] Allow update onto the same firmware version (SLB 9672)
      with -force parameter, also when using a configuration file.
      This parameter is not necessary if the TPM is in non-operational mode.
- [I] Introducing new name schema with major TPM version for specifying the
      TPM target firmware image name (SLB 9672).
- [I] The application can be started from a different working
      directory than from the directory where the application files are stored.
- [I] Indentation uses spaces instead of tabs in source code files.

Changes since version 01.01.2529.00
- [I] Add support for OpenSSL 1.1
- [F] Fix sporadic error during firmware update on SLB 9670 device
- [N] Update TPM1.2 with owner authorization
- [I] Support -ownerauth parameter for command line options
      -update tpm12-takeownership and -tpm12-clearownership
- [F] Fix sporadic TPM connection error (0xE0295200) after successful update on
      platforms with temporarily disabled TPM support
- [N] Add support for well-known owner authorization secret

Changes since version 01.01.2459.00
- [F] Prevent update interruption in case TPM and or linux kernel returns device
      or resource busy.
- [I] Change source code license
- [I] Resolve scan-build warnings

Changes since version 01.01.2168.00
- [I] Changed default access mode to /dev/tpm0
- [I] Improved command line parsing
- [I] Show test result if TPM2.0 is in failure mode.
- [I] Improved user interface if TPM1.2 self-test failed


5.3 Known Bugs and Limitations

none


5.4 Further Information

- In case the TPM Firmware Update process has been interrupted or the TPM is in
  non-operational mode (SLB 9672):
  1. Reboot the system before retrying the update.
     In this case TPM Firmware Update must be resumed with the exact same
     firmware image that was used when the interruption occurred.
     The number of resume attempts is limited. For the exact number of resume
     attempts supported by a particular TPM model please consult TPM
     documentation or contact your local Infineon representative.
  2. Check if the device /dev/tpm0 is available, if yes, try the update again.
  3. If not, following steps may help:
  3a. On x64 platforms TPMFactoryUpd can be called with command-line option
      "-access-mode 1".
  3b. On x64 or ARM platforms with kernel versions older than 6.1 the kernel
      needs to be replaced, to ignore errors during driver start-up.
      Please search the support pages of your Linux distribution for
      available kernel versions and how to (temporarily) replace them.
      Run TPMFactoryUpd again and be sure the update completed successfully.

- TPMFactoryUpd will fail to connect to /dev/tpm0 if /dev/tpm0 is in use by
  another process. For example the TPM device could be already used by an
  installed TSS software. In this case find out which process uses /dev/tpm0
  (e.g. "sudo lsof | grep /dev/tpm0") and note the process ID (PID). Stop the
  process and verify that the /dev/tpm0 is no longer in
  use (e.g. "sudo lsof | grep /dev/tpm0").

- Note that several Raspberry Pi SoCs have a bug regarding the I2C clock
  stretching detection (older than Raspberry Pi 5).
  This is also described here: https://github.com/raspberrypi/linux/issues/4884
  Thus, it is recommended to use the soft-spi driver. Note that on
  Raspberry Pi 4, the soft-spi driver occasionally has a bug related to clock
  cycles.
  A driver change that enables retransmissions in such cases is included in the
  Linux Kernel 6.6.
