/**
 *  @brief      Windows direct TPM TIS transport through the proven TVicPort.sys interface for Infineon TPMFactoryUpd.
 *
 *  This is the Windows equivalent of the official Linux memory-based
 *  access-mode 1 path from TPMFactoryUpd 02.03.4733.00:
 *
 *      DeviceAccess_Initialize()
 *      TIS_IsAccessValid()
 *      TIS_IsActiveLocality()
 *      TIS_RequestUse()
 *      TIS_Transceive()
 *
 *  No Windows TPM Base Services call is used by this transport.
 */

#include "StdInclude.h"
#include "TpmIO.h"
#include "Logging.h"
#include "DeviceAccess.h"
#include "Platform.h"
#include "TPM_TIS.h"
#include "PropertyStorage.h"

BOOL g_fConnected = FALSE;

#define PROPERTY_LOCALITY             L"Locality"
#define PROPERTY_KEEP_LOCALITY_ACTIVE L"KeepLocalityActive"

static BOOL s_fIsLocalitySet = FALSE;

_Check_return_
unsigned int
TPMIO_Connect(void)
{
    unsigned int unReturnValue = RC_E_FAIL;
    UINT32 unMode = 0;
    unsigned int unLocality = 0;
    BOOL bFlag = FALSE;
    BOOL fKeepLocalityActive = FALSE;
    BOOL fDeviceInitialized = FALSE;

    LOGGING_WRITE_LEVEL4(LOGGING_METHOD_ENTRY_STRING);

    do
    {
        if (g_fConnected)
        {
            unReturnValue = RC_E_ALREADY_CONNECTED;
            break;
        }

        if (!PropertyStorage_GetUIntegerValueByKey(
                PROPERTY_TPM_DEVICE_ACCESS_MODE, &unMode) ||
            TPM_DEVICE_ACCESS_MEMORY_BASED != unMode)
        {
            unReturnValue = RC_E_INTERNAL;
            LOGGING_WRITE_LEVEL1(
                L"Windows direct build supports access mode 1 (memory/TIS) only.");
            break;
        }

        if (!PropertyStorage_GetUIntegerValueByKey(PROPERTY_LOCALITY, &unLocality))
        {
            unReturnValue = RC_E_INTERNAL;
            break;
        }

        unReturnValue = DeviceAccess_Initialize((BYTE)unLocality);
        if (RC_SUCCESS != unReturnValue)
        {
            LOGGING_WRITE_LEVEL1_FMT(
                L"Error initializing direct TPM MMIO access: 0x%.8X",
                unReturnValue);
            break;
        }
        fDeviceInitialized = TRUE;

        LOGGING_WRITE_LEVEL4(L"Using direct memory/TIS access routines.");
        LOGGING_WRITE_LEVEL4_FMT(L"Using Locality: %d", unLocality);

        unReturnValue = TIS_IsAccessValid((BYTE)unLocality, &bFlag);
        if (RC_SUCCESS != unReturnValue)
        {
            LOGGING_WRITE_LEVEL1_FMT(
                L"Error checking TIS access-valid: 0x%.8X",
                unReturnValue);
            break;
        }

        if (!bFlag)
        {
            unReturnValue = RC_E_NOT_READY;
            LOGGING_WRITE_LEVEL1_FMT(
                L"TPM TIS register block is present but ACCESS.VALID is not set (0x%.8X).",
                unReturnValue);
            break;
        }

        unReturnValue = TIS_IsActiveLocality(
            (BYTE)unLocality, &s_fIsLocalitySet);
        if (RC_SUCCESS != unReturnValue)
        {
            LOGGING_WRITE_LEVEL1_FMT(
                L"Could not check active TPM locality: 0x%.8X",
                unReturnValue);
            break;
        }

        if (!PropertyStorage_GetBooleanValueByKey(
                PROPERTY_KEEP_LOCALITY_ACTIVE, &fKeepLocalityActive))
        {
            unReturnValue = RC_E_INTERNAL;
            break;
        }

        if (fKeepLocalityActive)
        {
            unReturnValue = TIS_RequestUse((BYTE)unLocality);
            if (RC_SUCCESS != unReturnValue)
            {
                LOGGING_WRITE_LEVEL1_FMT(
                    L"Could not request TPM locality: 0x%.8X",
                    unReturnValue);
                break;
            }
            TIS_KeepLocalityActive();
        }

        g_fConnected = TRUE;
        unReturnValue = RC_SUCCESS;
        LOGGING_WRITE_LEVEL4(L"Connected directly to the physical TPM TIS interface.");
    }
    WHILE_FALSE_END;

    if (RC_SUCCESS != unReturnValue && fDeviceInitialized)
    {
        IGNORE_RETURN_VALUE(DeviceAccess_Uninitialize((BYTE)unLocality));
    }

    LOGGING_WRITE_LEVEL4_FMT(LOGGING_METHOD_EXIT_STRING_RET_VAL, unReturnValue);
    return unReturnValue;
}

_Check_return_
unsigned int
TPMIO_Disconnect(void)
{
    unsigned int unReturnValue = RC_E_FAIL;
    UINT32 unMode = 0;
    unsigned int unLocality = 0;
    BOOL fKeepLocalityActive = FALSE;

    LOGGING_WRITE_LEVEL4(LOGGING_METHOD_ENTRY_STRING);

    do
    {
        if (!g_fConnected)
        {
            unReturnValue = RC_E_NOT_CONNECTED;
            break;
        }

        if (!PropertyStorage_GetUIntegerValueByKey(
                PROPERTY_TPM_DEVICE_ACCESS_MODE, &unMode) ||
            TPM_DEVICE_ACCESS_MEMORY_BASED != unMode)
        {
            unReturnValue = RC_E_INTERNAL;
            break;
        }

        if (!PropertyStorage_GetUIntegerValueByKey(PROPERTY_LOCALITY, &unLocality) ||
            !PropertyStorage_GetBooleanValueByKey(
                PROPERTY_KEEP_LOCALITY_ACTIVE, &fKeepLocalityActive))
        {
            unReturnValue = RC_E_INTERNAL;
            break;
        }

        if (fKeepLocalityActive)
        {
            unReturnValue = TIS_ReleaseActiveLocality((BYTE)unLocality);
            if (RC_SUCCESS != unReturnValue)
            {
                LOGGING_WRITE_LEVEL1_FMT(
                    L"Could not release TPM locality: 0x%.8X",
                    unReturnValue);
                break;
            }
        }

        if (s_fIsLocalitySet)
        {
            unReturnValue = TIS_RequestUse((BYTE)unLocality);
            if (RC_SUCCESS != unReturnValue)
            {
                LOGGING_WRITE_LEVEL1_FMT(
                    L"Could not restore original TPM locality: 0x%.8X",
                    unReturnValue);
                break;
            }
            s_fIsLocalitySet = FALSE;
        }

        unReturnValue = DeviceAccess_Uninitialize((BYTE)unLocality);
        if (RC_SUCCESS != unReturnValue)
            break;

        g_fConnected = FALSE;
        unReturnValue = RC_SUCCESS;
    }
    WHILE_FALSE_END;

    LOGGING_WRITE_LEVEL4_FMT(LOGGING_METHOD_EXIT_STRING_RET_VAL, unReturnValue);
    return unReturnValue;
}

_Check_return_
unsigned int
TPMIO_Transmit(
    _In_bytecount_(PunRequestBufferSize) const BYTE* PrgbRequestBuffer,
    _In_ unsigned int PunRequestBufferSize,
    _Out_bytecap_(*PpunResponseBufferSize) BYTE* PrgbResponseBuffer,
    _Inout_ unsigned int* PpunResponseBufferSize,
    _In_ unsigned int PunMaxDuration)
{
    unsigned int unReturnValue = RC_E_FAIL;
    UINT32 unMode = 0;
    unsigned int unLocality = 0;

    LOGGING_WRITE_LEVEL4(LOGGING_METHOD_ENTRY_STRING);

    do
    {
        if (NULL == PrgbRequestBuffer ||
            NULL == PrgbResponseBuffer ||
            NULL == PpunResponseBufferSize)
        {
            unReturnValue = RC_E_BAD_PARAMETER;
            break;
        }

        if (!g_fConnected)
        {
            unReturnValue = RC_E_NOT_CONNECTED;
            break;
        }

        if (!PropertyStorage_GetUIntegerValueByKey(
                PROPERTY_TPM_DEVICE_ACCESS_MODE, &unMode) ||
            TPM_DEVICE_ACCESS_MEMORY_BASED != unMode)
        {
            unReturnValue = RC_E_INTERNAL;
            break;
        }

        if (!PropertyStorage_GetUIntegerValueByKey(PROPERTY_LOCALITY, &unLocality))
        {
            unReturnValue = RC_E_INTERNAL;
            break;
        }

        unReturnValue = TIS_Transceive(
            (BYTE)unLocality,
            PrgbRequestBuffer,
            (UINT16)PunRequestBufferSize,
            PrgbResponseBuffer,
            (UINT16*)PpunResponseBufferSize,
            PunMaxDuration);

        if (RC_SUCCESS != unReturnValue)
            LOGGING_WRITE_LEVEL1(L"Transmission of data via direct TIS failed.");
    }
    WHILE_FALSE_END;

    LOGGING_WRITE_LEVEL4_FMT(LOGGING_METHOD_EXIT_STRING_RET_VAL, unReturnValue);
    return unReturnValue;
}

_Check_return_
unsigned int
TPMIO_ReadRegister(
    _In_ unsigned int PunRegisterAddress,
    _Inout_ BYTE* PpbRegisterValue)
{
    UINT32 unMode = 0;

    if (NULL == PpbRegisterValue)
        return RC_E_BAD_PARAMETER;

    if (!PropertyStorage_GetUIntegerValueByKey(
            PROPERTY_TPM_DEVICE_ACCESS_MODE, &unMode) ||
        TPM_DEVICE_ACCESS_MEMORY_BASED != unMode)
        return RC_E_INTERNAL;

    *PpbRegisterValue = DeviceAccess_ReadByte(PunRegisterAddress);
    return RC_SUCCESS;
}

_Check_return_
unsigned int
TPMIO_WriteRegister(
    _In_ unsigned int PunRegisterAddress,
    _In_ BYTE PbRegisterValue)
{
    UINT32 unMode = 0;

    if (!PropertyStorage_GetUIntegerValueByKey(
            PROPERTY_TPM_DEVICE_ACCESS_MODE, &unMode) ||
        TPM_DEVICE_ACCESS_MEMORY_BASED != unMode)
        return RC_E_INTERNAL;

    DeviceAccess_WriteByte(PunRegisterAddress, PbRegisterValue);
    return RC_SUCCESS;
}
