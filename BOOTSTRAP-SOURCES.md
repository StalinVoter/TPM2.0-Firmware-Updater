# Version 0.86 bootstrap inputs

- Native C code and launcher: the verified full 0.831 source archive, retained
  unchanged, with its existing native identity/policy protocol.
- Application scripts: the released 0.86 portable workflow, including the
  0.85 replacement-TPM and numeric BitLocker fixes.
- Build scripts and MSVC/SDK provisioning: the 0.831 build system updated for
  the 0.86 identity, tests, and published files.
- Driver: exact supplied TVicPort.sys, SHA-256
  9c9ab56c8bcf5ec958e7c2346f23a3027f69abdf8af923b591518eee64ad98ad.
- Firmware: all 12 original pinned images and vendor license/readme.
- Build prerequisites: the build downloads Microsoft's signed Visual Studio
  Build Tools bootstrapper from the official Visual Studio release endpoint
  only when prerequisites need provisioning. No separate driver installer is used.

See PROVENANCE.md and BUILDING.md for details.
