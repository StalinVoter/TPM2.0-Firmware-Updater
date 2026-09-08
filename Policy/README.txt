OEM TPM2_PolicyOR platform-policy support
=========================================

No policy file is needed when the live TPM reports either:

  platformAuth = Empty Buffer

or a non-empty platformAuth whose SHA-256 platform-policy digest is exactly
Infineon's default FieldUpgrade PolicyCommandCode digest:

  652351CB9FE7D86EB244A95E5AD4DDB79C1138C0BFE15B1664F69F5E74C94539

Legacy firmware 5.0 may reject TPM_CAP_AUTH_POLICIES with TPM return code
0x000001C4, so it cannot report the live digest. With non-empty platformAuth in
that state, V0.831 refuses to use tpm20-platformpolicy. V9.3 target evidence showed
the policy session being rejected by FieldUpgradeStartVendor with
TPM_RC_AUTH_UNAVAILABLE (0x0000012F), meaning no usable authPolicy was available
for the platform entity. A PolicyFile cannot create a missing platform
authPolicy.

For an OEM PolicyOR policy, obtain the exact Infineon policy file supplied for
that computer/firmware and run:

  TPM-Updater.cmd -PolicyFile "C:\path\policy.cfg"

V0.831 accepts the [POLICYOR_TPMFWUPDATE] section with 2 through 8 contiguous,
unique SHA-256 entries named PolicyDigest1 through PolicyDigest8. The set must
include Infineon's FieldUpgrade PolicyCommandCode digest shown above.

Before enabling a firmware-update checklist action, V0.831 computes:

  SHA256(zeroDigest || TPM_CC_PolicyOR || PolicyDigest1 || ... || PolicyDigestN)

using TPM wire byte order. V0.831 requires an exact digest match with the live
hierarchy authPolicy. If the TPM cannot report that policy, V0.831 rejects the
PolicyFile before enabling a firmware-update action.

A random file, an incomplete digest list, a SHA-1 policy, a reported-policy
digest mismatch, or any PolicyFile supplied while the live digest is
unqueryable is rejected.
