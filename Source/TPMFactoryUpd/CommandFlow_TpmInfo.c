/**
 *  @brief      Implements the command flow to retrieve information about the TPM1.2 or TPM2.0.
 *  @details    This module collects TPM Firmware Update related information via specific TPM commands.
 *              Afterwards the TPM related information is returned to the calling module.
 *  @file       CommandFlow_TpmInfo.c
 *
 *  Copyright 2014 - 2025 Infineon Technologies AG ( www.infineon.com )
 *
 *  Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 *  1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 *  2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 *  3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "CommandFlow_TpmInfo.h"
#include "FirmwareUpdate.h"

#ifdef WINDOWS
#include "TPM2_FieldUpgradeDataVendor.h"
#include "DeviceManagement.h"
#include <stdio.h>

/*
 * V0.831 read-only identity and policy probe.
 *
 * TPM_CAP_AUTH_POLICIES (0x00000009) returns TPML_TAGGED_POLICY.  The
 * Infineon MicroTSS in this source release predates that capability in its
 * generated union, so V0.831 sends this one GetCapability request directly and
 * reports the platform hierarchy policy on stderr.  The wrapper captures it
 * in the diagnostic log; it is not printed as normal UI chatter.
 */
static unsigned int
V94_ReadBe32(
    _In_reads_(4) const BYTE* Ppb)
{
    return ((unsigned int)Ppb[0] << 24) |
           ((unsigned int)Ppb[1] << 16) |
           ((unsigned int)Ppb[2] << 8)  |
           ((unsigned int)Ppb[3]);
}

static unsigned short
V94_ReadBe16(
    _In_reads_(2) const BYTE* Ppb)
{
    return (unsigned short)(
        ((unsigned int)Ppb[0] << 8) |
        ((unsigned int)Ppb[1]));
}

static unsigned int
V94_HashSize(
    _In_ unsigned short PusAlg)
{
    switch (PusAlg)
    {
        case 0x0004U: return 20U; /* TPM_ALG_SHA1 */
        case 0x000BU: return 32U; /* TPM_ALG_SHA256 */
        case 0x000CU: return 48U; /* TPM_ALG_SHA384 */
        case 0x000DU: return 64U; /* TPM_ALG_SHA512 */
        case 0x0012U: return 32U; /* TPM_ALG_SM3_256 */
        default:      return 0U;
    }
}

static void
V94_ReportPlatformPolicy(void)
{
    static const BYTE CrgbRequest[22] = {
        0x80, 0x01,                         /* TPM_ST_NO_SESSIONS */
        0x00, 0x00, 0x00, 0x16,             /* commandSize = 22 */
        0x00, 0x00, 0x01, 0x7A,             /* TPM_CC_GetCapability */
        0x00, 0x00, 0x00, 0x09,             /* TPM_CAP_AUTH_POLICIES */
        0x40, 0x00, 0x00, 0x0C,             /* TPM_RH_PLATFORM */
        0x00, 0x00, 0x00, 0x01              /* propertyCount = 1 */
    };

    BYTE rgbResponse[256];
    unsigned int unResponseSize = (unsigned int)sizeof(rgbResponse);
    unsigned int unTransmit = RC_E_FAIL;
    unsigned int unResponseCode = 0U;
    unsigned int unDeclaredSize = 0U;
    unsigned int unCapability = 0U;
    unsigned int unCount = 0U;
    unsigned int unOffset = 0U;
    unsigned int unIndex = 0U;
    BOOL fFound = FALSE;

    Platform_MemorySet(rgbResponse, 0, sizeof(rgbResponse));

    unTransmit = DeviceManagement_Transmit(
        CrgbRequest,
        (unsigned int)sizeof(CrgbRequest),
        rgbResponse,
        &unResponseSize);

    if (RC_SUCCESS != unTransmit || unResponseSize < 10U)
    {
        fprintf(
            stderr,
            "[V0.831 POLICY] platformPolicy=unavailable transport=0x%08X responseBytes=%u\n",
            unTransmit,
            unResponseSize);
        fflush(stderr);
        return;
    }

    unDeclaredSize = V94_ReadBe32(&rgbResponse[2]);
    if (unDeclaredSize < 10U || unDeclaredSize > unResponseSize)
    {
        fprintf(
            stderr,
            "[V0.831 POLICY] platformPolicy=unavailable malformedResponse declaredBytes=%u responseBytes=%u\n",
            unDeclaredSize,
            unResponseSize);
        fflush(stderr);
        return;
    }

    unResponseSize = unDeclaredSize;
    unResponseCode = V94_ReadBe32(&rgbResponse[6]);
    if (0U != unResponseCode)
    {
        if (0x000001C4U == unResponseCode)
        {
            /*
             * Legacy SLB9665 5.0 firmware returns TPM_RC_VALUE for parameter
             * one because TPM_CAP_AUTH_POLICIES is not implemented.  This is
             * a valid TPM error response, not a transport failure.
             */
            fprintf(
                stderr,
                "[V0.831 POLICY] platformPolicy=unsupported-capability tpmRc=0x%08X\n",
                unResponseCode);
        }
        else
        {
            fprintf(
                stderr,
                "[V0.831 POLICY] platformPolicy=unavailable tpmRc=0x%08X\n",
                unResponseCode);
        }
        fflush(stderr);
        return;
    }

    if (unResponseSize < 19U)
    {
        fprintf(
            stderr,
            "[V0.831 POLICY] platformPolicy=unavailable shortSuccess responseBytes=%u\n",
            unResponseSize);
        fflush(stderr);
        return;
    }

    unCapability = V94_ReadBe32(&rgbResponse[11]);
    if (0x00000009U != unCapability)
    {
        fprintf(
            stderr,
            "[V0.831 POLICY] platformPolicy=unavailable capability=0x%08X\n",
            unCapability);
        fflush(stderr);
        return;
    }

    unCount = V94_ReadBe32(&rgbResponse[15]);
    unOffset = 19U;

    for (unIndex = 0U; unIndex < unCount; unIndex++)
    {
        unsigned int unHandle = 0U;
        unsigned short usAlg = 0U;
        unsigned int unDigestSize = 0U;
        unsigned int unByte = 0U;

        if (unOffset + 6U > unResponseSize)
            break;

        unHandle = V94_ReadBe32(&rgbResponse[unOffset]);
        unOffset += 4U;

        usAlg = V94_ReadBe16(&rgbResponse[unOffset]);
        unOffset += 2U;

        unDigestSize = V94_HashSize(usAlg);
        if (0U == unDigestSize || unOffset + unDigestSize > unResponseSize)
            break;

        if (0x4000000CU == unHandle)
        {
            fprintf(
                stderr,
                "[V0.831 POLICY] platformPolicy handle=0x%08X alg=0x%04X digest=",
                unHandle,
                (unsigned int)usAlg);

            for (unByte = 0U; unByte < unDigestSize; unByte++)
                fprintf(stderr, "%02X", (unsigned int)rgbResponse[unOffset + unByte]);

            fprintf(stderr, "\n");
            fflush(stderr);
            fFound = TRUE;
            break;
        }

        unOffset += unDigestSize;
    }

    if (!fFound)
    {
        fprintf(stderr, "[V0.831 POLICY] platformPolicy=none\n");
        fflush(stderr);
    }
}
#endif

/**
 *  @brief      Processes a sequence of TPM info related commands.
 *  @details    This function collects TPM Firmware Update related information via specific TPM commands.
 *              Afterwards the TPM related information is returned to the calling module.
 *              The function utilizes the MicroTss library.
 *
 *  @param      PpTpmInfo               Pointer to an initialized IfxInfo structure to be filled in.
 *  @retval     RC_SUCCESS              The operation completed successfully.
 *  @retval     RC_E_BAD_PARAMETER      An invalid parameter was passed to the function. PpTpmInfo was invalid.
 *  @retval     RC_E_FAIL               An unexpected error occurred.
 *  @retval     ...                     Error codes from called functions.
 */
_Check_return_
unsigned int
CommandFlow_TpmInfo_Execute(
    _Inout_ IfxInfo* PpTpmInfo)
{
    unsigned int unReturnValue = RC_E_FAIL;

    LOGGING_WRITE_LEVEL4(LOGGING_METHOD_ENTRY_STRING);

    do
    {
        unsigned int unVersionNameSize = 0;

        // Check parameters
        if (NULL == PpTpmInfo ||
                PpTpmInfo->hdr.unType != STRUCT_TYPE_TpmInfo ||
                PpTpmInfo->hdr.unSize != sizeof(IfxInfo))
        {
            unReturnValue = RC_E_BAD_PARAMETER;
            ERROR_STORE(unReturnValue, L"Bad parameter detected. IfxInfo structure is not in the correct state.");
            break;
        }

        PpTpmInfo->hdr.unReturnCode = RC_E_FAIL;
        PpTpmInfo->unRemainingUpdates = REMAINING_UPDATES_UNAVAILABLE; // -1
        PpTpmInfo->unRemainingUpdatesSelf = REMAINING_UPDATES_UNAVAILABLE; // -1
        unVersionNameSize = RG_LEN(PpTpmInfo->wszVersionName);

        // Get the actual image info
        unReturnValue = FirmwareUpdate_GetImageInfo(PpTpmInfo->wszVersionName, &unVersionNameSize, &PpTpmInfo->sTpmState, &PpTpmInfo->unRemainingUpdates);
        if (RC_SUCCESS != unReturnValue)
            break;

#ifdef WINDOWS
        if (PpTpmInfo->sTpmState.attribs.tpm20)
        {
            fprintf(
                stderr,
                "[V0.831 IDENTITY] infineon=%s unsupportedChip=%s\n",
                PpTpmInfo->sTpmState.attribs.infineon ? "Yes" : "No",
                PpTpmInfo->sTpmState.attribs.unsupportedChip ? "Yes" : "No");
            fflush(stderr);
            V94_ReportPlatformPolicy();
        }
#endif

        // Check for TPM2.0 based firmware update loader
        if (PpTpmInfo->sTpmState.attribs.tpmHasFULoader20)
        {
            // Get field upgrade counter (same version)
            unReturnValue = FirmwareUpdate_GetTpm20FieldUpgradeCounterSelf(&PpTpmInfo->unRemainingUpdatesSelf);
            if (RC_SUCCESS != unReturnValue)
                break;
        }

#ifdef WINDOWS
        // Check if FieldUpgrade commands can be submitted
        if (TPM_DEVICE_ACCESS_WIN_TBS == DeviceManagement_GetDeviceAccessMode())
        {
            TSS_TPM2B_MAX_BUFFER dummyData;
            dummyData.size = 0;
            unsigned int unReturnValueTemp = TSS_TPM2_FieldUpgradeDataVendor(&dummyData);
            if ((TPM_E_COMMAND_BLOCKED | RC_TPM_MASK) == unReturnValueTemp)
            {
                LOGGING_WRITE_LEVEL4(L"TPM2_FieldUpgradeDataVendor command was blocked by TBS!");
                PpTpmInfo->fFuCommandsBlocked = TRUE;
            }
            else
            {
                PpTpmInfo->fFuCommandsBlocked = FALSE;
            }
        }
#endif

        PpTpmInfo->hdr.unReturnCode = RC_SUCCESS;
    }
    WHILE_FALSE_END;

    LOGGING_WRITE_LEVEL4_FMT(LOGGING_METHOD_EXIT_STRING_RET_VAL, unReturnValue);

    return unReturnValue;
}
