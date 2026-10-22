# Source and release provenance

## Native source baseline

Archive: Infineon-TPM-Firmware-Updater-v0.831-SOURCE.zip
SHA-256: 0364e60357b0579fbc87301ad8214734dc6eb9f39246dbd168ff9a2bac9661e5

The archive CRC and its supplied archive checksum were verified. All 195 files
listed in its original source manifest were also verified before carrying the
tree forward. Every file under Source is retained byte-for-byte, including the
launcher and native identity/policy protocol. Original vendor notices remain.

## Current runtime baseline

Archive: Infineon-TPM-Firmware-Updater-v0.86-PORTABLE.zip
SHA-256: c7547702fb44a4fb4ff133e26f08d7df997d539859ac5ed0418b6d5ce09a0731

The current runtime PowerShell files, regression suite, runtime verifier, policy
readme and portable instructions were carried into the source layout. Build
metadata, publication lists and older test expectations were updated for 0.86.
The native diagnostic tags remain V0.831 on both sides of the protocol.

No compiled updater EXE is needed in this source repository. The build creates
both executable files. The driver and firmware are the supplied vendor binaries;
this repository does not contain their internal source code. Their license
materials are preserved under the original names.
