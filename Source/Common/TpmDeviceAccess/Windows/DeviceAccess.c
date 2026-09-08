/**
 *  @brief      Windows physical TPM access through the exact legacy
 *              TVicPort.sys interface used by the known-good Infineon
 *              TPMFactoryUpd.exe.
 *
 *  This implementation was reconstructed from the user-supplied binaries:
 *
 *      TPMFactoryUpd.exe
 *      SHA-256 ba05c8edd44183cf0e4e5a993a89c506a42c1113655a879c07f5cf5b8400b37e
 *
 *      TVicPort.sys
 *      SHA-256 9c9ab56c8bcf5ec958e7c2346f23a3027f69abdf8af923b591518eee64ad98ad
 *
 *  Proven interface:
 *      service name:       TVICPORT
 *      device path:        \\.\TVicPortDevice0
 *      map IOCTL:          0x80002008
 *      unmap IOCTL:        0x8000200C
 *      TPM MMIO window:    0xFED40000..0xFED44FFF
 *
 *  The original working updater maps this same TPM window and then performs
 *  direct TIS register accesses from user mode.  No TVicPort.dll, cpd64.exe,
 *  TVicPort installer, Windows TBS, WMI or Get-Tpm is required here.
 */

#include "StdInclude.h"
#include "DeviceAccess.h"
#include "Logging.h"
#include "Globals.h"

#include <windows.h>
#include <winsvc.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <excpt.h>

#define TVIC_SERVICE_NAME_A        "TVICPORT"
#define TVIC_DEVICE_PATH_A         "\\\\.\\TVicPortDevice0"
#define TVIC_DRIVER_FILE_A         "TVicPort.sys"

#define TVIC_IOCTL_MAP_PHYSICAL    0x80002008UL
#define TVIC_IOCTL_UNMAP_PHYSICAL  0x8000200CUL

typedef struct _TVIC_MAP_REQUEST
{
    DWORD      InterfaceType;  /* INTERFACE_TYPE Isa == 1 */
    DWORD      BusNumber;
    ULONGLONG  BusAddress;
    DWORD      AddressSpace;
    DWORD      Length;
} TVIC_MAP_REQUEST;

typedef char TVIC_MAP_REQUEST_must_be_24_bytes[(sizeof(TVIC_MAP_REQUEST) == 24U) ? 1 : -1];

static void
DeviceAccess_Diag(_In_z_ const char* PszFormat, ...)
{
    va_list args;
    va_start(args, PszFormat);
    fputs("[V0.831 DIRECT] ", stderr);
    vfprintf(stderr, PszFormat, args);
    fputc('\n', stderr);
    fflush(stderr);
    va_end(args);
}

static HANDLE    s_hDevice = INVALID_HANDLE_VALUE;
static SC_HANDLE s_hScm = NULL;
static SC_HANDLE s_hService = NULL;

static BOOL s_fServiceCreatedByUs = FALSE;
static BOOL s_fServiceStartedByUs = FALSE;
static BOOL s_fServiceWasRunning = FALSE;

static ULONG_PTR s_unMappedPointer = 0U;
/*
 * TVicPort.sys returns only the low DWORD of the adjusted user pointer even
 * though ZwMapViewOfSection uses a 64-bit BaseAddress on x64.
 */
static DWORD s_dwDriverMappedToken = 0U;
static HANDLE s_hInstanceMutex = NULL;

static BOOL
DeviceAccess_IsAddressValid(
    _In_ unsigned int PunMemoryAddress,
    _In_ unsigned int PunWidth)
{
    ULONGLONG ullStart = (ULONGLONG)PunMemoryAddress;
    ULONGLONG ullEnd = ullStart + (ULONGLONG)PunWidth;
    ULONGLONG ullBase = (ULONGLONG)TPM_DEFAULT_MEM_BASE;
    ULONGLONG ullLimit = ullBase + (ULONGLONG)TPM_DEFAULT_MEM_SIZE;

    return (ullStart >= ullBase &&
            ullEnd >= ullStart &&
            ullEnd <= ullLimit);
}

static BOOL
DeviceAccess_IsReadableCommittedRegion(
    _In_ const MEMORY_BASIC_INFORMATION* Pmbi)
{
    DWORD unProtect = 0U;

    if (NULL == Pmbi)
        return FALSE;

    if (MEM_COMMIT != Pmbi->State)
        return FALSE;

    unProtect = Pmbi->Protect;

    if (0U != (unProtect & PAGE_GUARD) ||
        0U != (unProtect & PAGE_NOACCESS))
        return FALSE;

    switch (unProtect & 0xFFU)
    {
        case PAGE_READONLY:
        case PAGE_READWRITE:
        case PAGE_WRITECOPY:
        case PAGE_EXECUTE_READ:
        case PAGE_EXECUTE_READWRITE:
        case PAGE_EXECUTE_WRITECOPY:
            return TRUE;

        default:
            return FALSE;
    }
}

static BOOL
DeviceAccess_ReconstructMappedPointer(
    _In_ DWORD PunLow32,
    _Out_ ULONG_PTR* PpunPointer)
{
    SYSTEM_INFO systemInfo;
    ULONG_PTR unAddress = 0U;
    ULONG_PTR unMaximum = 0U;
    ULONG_PTR unCandidate = 0U;
    ULONG_PTR unMatch = 0U;
    unsigned int unMatches = 0U;
    MEMORY_BASIC_INFORMATION mbi;

    if (NULL == PpunPointer)
        return FALSE;

    *PpunPointer = 0U;

    ZeroMemory(&systemInfo, sizeof(systemInfo));
    GetSystemInfo(&systemInfo);

    unAddress = (ULONG_PTR)systemInfo.lpMinimumApplicationAddress;
    unMaximum = (ULONG_PTR)systemInfo.lpMaximumApplicationAddress;

    DeviceAccess_Diag(
        "Reconstructing full x64 mapping from driver low-DWORD token 0x%08lX; scanning user VA %p..%p",
        PunLow32,
        systemInfo.lpMinimumApplicationAddress,
        systemInfo.lpMaximumApplicationAddress);

    while (unAddress < unMaximum)
    {
        SIZE_T unResult = 0U;
        ULONG_PTR unRegionBase = 0U;
        ULONG_PTR unRegionEnd = 0U;
        ULONGLONG ullFirstK = 0ULL;
        ULONGLONG ullLastK = 0ULL;
        ULONGLONG ullLow = (ULONGLONG)PunLow32;
        const ULONGLONG ullStep = 0x100000000ULL;

        ZeroMemory(&mbi, sizeof(mbi));

        unResult = VirtualQuery(
            (LPCVOID)unAddress,
            &mbi,
            sizeof(mbi));

        if (0U == unResult)
        {
            ULONG_PTR unNext = unAddress + 0x1000U;
            if (unNext <= unAddress)
                break;
            unAddress = unNext;
            continue;
        }

        unRegionBase = (ULONG_PTR)mbi.BaseAddress;

        if ((ULONG_PTR)-1 - unRegionBase < (ULONG_PTR)mbi.RegionSize)
            unRegionEnd = (ULONG_PTR)-1;
        else
            unRegionEnd = unRegionBase + (ULONG_PTR)mbi.RegionSize;

        if (DeviceAccess_IsReadableCommittedRegion(&mbi) &&
            unRegionEnd > unRegionBase)
        {
            ULONGLONG ullBase = (ULONGLONG)unRegionBase;
            ULONGLONG ullEndExclusive = (ULONGLONG)unRegionEnd;

            if (ullEndExclusive > ullLow)
            {
                if (ullBase <= ullLow)
                    ullFirstK = 0ULL;
                else
                    ullFirstK = (ullBase - ullLow + ullStep - 1ULL) / ullStep;

                ullLastK = (ullEndExclusive - 1ULL - ullLow) / ullStep;

                if (ullFirstK <= ullLastK)
                {
                    ULONGLONG ullCandidate = ullLow + (ullFirstK * ullStep);

                    if (ullCandidate >= ullBase &&
                        ullCandidate < ullEndExclusive &&
                        ullCandidate <= (ULONGLONG)(ULONG_PTR)-1)
                    {
                        unCandidate = (ULONG_PTR)ullCandidate;
                        unMatches++;

                        DeviceAccess_Diag(
                            "Low32 candidate #%u: full=%p regionBase=%p regionSize=0x%Ix State=0x%lX Protect=0x%lX Type=0x%lX",
                            unMatches,
                            (void*)unCandidate,
                            mbi.BaseAddress,
                            mbi.RegionSize,
                            mbi.State,
                            mbi.Protect,
                            mbi.Type);

                        if (1U == unMatches)
                            unMatch = unCandidate;
                    }
                }
            }
        }

        if (unRegionEnd <= unAddress)
            break;

        unAddress = unRegionEnd;
    }

    if (1U != unMatches)
    {
        DeviceAccess_Diag(
            "Full-pointer reconstruction is ambiguous/failed: %u readable committed candidate(s) matched low DWORD 0x%08lX.",
            unMatches,
            PunLow32);
        return FALSE;
    }

    *PpunPointer = unMatch;
    DeviceAccess_Diag(
        "Reconstructed full mapped pointer uniquely: lowDWORD=0x%08lX full=%p",
        PunLow32,
        (void*)unMatch);

    return TRUE;
}

static BOOL
DeviceAccess_BuildDriverPath(
    _Out_writes_z_(PunPathLength) char* PszPath,
    _In_ DWORD PunPathLength)
{
    DWORD unLength = 0U;
    char* pszSlash = NULL;

    if (NULL == PszPath || 0U == PunPathLength)
        return FALSE;

    unLength = GetModuleFileNameA(NULL, PszPath, PunPathLength);
    if (0U == unLength || unLength >= PunPathLength)
        return FALSE;

    pszSlash = strrchr(PszPath, '\\');
    if (NULL == pszSlash)
        return FALSE;

    *(pszSlash + 1) = '\0';

    if (0 != strcat_s(PszPath, PunPathLength, TVIC_DRIVER_FILE_A))
        return FALSE;

    return TRUE;
}

static BOOL
DeviceAccess_OpenDevice(void)
{
    if (INVALID_HANDLE_VALUE != s_hDevice) return TRUE;
    SetLastError(ERROR_SUCCESS);
    s_hDevice = CreateFileA(TVIC_DEVICE_PATH_A, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (INVALID_HANDLE_VALUE == s_hDevice) {
        DeviceAccess_Diag("CreateFile(%s) failed: Win32=%lu", TVIC_DEVICE_PATH_A, GetLastError());
        return FALSE;
    }
    DeviceAccess_Diag("Opened %s successfully; handle=%p", TVIC_DEVICE_PATH_A, s_hDevice);
    return TRUE;
}

static BOOL
DeviceAccess_QueryServiceRunning(
    _In_ SC_HANDLE PhService,
    _Out_ BOOL* PfRunning)
{
    SERVICE_STATUS status;

    if (NULL == PfRunning)
        return FALSE;

    *PfRunning = FALSE;
    ZeroMemory(&status, sizeof(status));

    if (!QueryServiceStatus(PhService, &status))
        return FALSE;

    *PfRunning = (SERVICE_RUNNING == status.dwCurrentState);
    return TRUE;
}

static BOOL
DeviceAccess_WaitForServiceState(
    _In_ SC_HANDLE PhService,
    _In_ DWORD PunWantedState,
    _In_ DWORD PunTimeoutMs)
{
    DWORD unStart = GetTickCount();

    for (;;)
    {
        SERVICE_STATUS status;
        ZeroMemory(&status, sizeof(status));

        if (!QueryServiceStatus(PhService, &status))
            return FALSE;

        if (PunWantedState == status.dwCurrentState)
            return TRUE;

        if ((GetTickCount() - unStart) >= PunTimeoutMs)
            return FALSE;

        Sleep(100U);
    }
}

static void
DeviceAccess_CloseServiceHandles(void)
{
    if (NULL != s_hService)
    {
        CloseServiceHandle(s_hService);
        s_hService = NULL;
    }

    if (NULL != s_hScm)
    {
        CloseServiceHandle(s_hScm);
        s_hScm = NULL;
    }
}

static BOOL
DeviceAccess_EnsureDriverRunning(void)
{
    char szDriverPath[MAX_PATH];
    DWORD unError = ERROR_SUCCESS;

    ZeroMemory(szDriverPath, sizeof(szDriverPath));

    /*
     * Match the old known-good updater's first behavior: if the device can
     * already be opened, do not modify service state at all.
     */
    if (DeviceAccess_OpenDevice()) {
        DeviceAccess_Diag("TVICPORT device already available; service state left untouched.");
        return TRUE;
    }

    s_hScm = OpenSCManagerA(
        NULL,
        NULL,
        SC_MANAGER_CONNECT | SC_MANAGER_CREATE_SERVICE);

    if (NULL == s_hScm)
    {
        LOGGING_WRITE_LEVEL1_FMT(
            L"OpenSCManager failed for TVICPORT (Win32 error %u).",
            GetLastError());
        return FALSE;
    }

    s_hService = OpenServiceA(
        s_hScm,
        TVIC_SERVICE_NAME_A,
        SERVICE_START | SERVICE_STOP | SERVICE_QUERY_STATUS | DELETE);

    if (NULL != s_hService)
    {
        BOOL fRunning = FALSE;

        if (!DeviceAccess_QueryServiceRunning(s_hService, &fRunning))
        {
            LOGGING_WRITE_LEVEL1_FMT(
                L"QueryServiceStatus failed for TVICPORT (Win32 error %u).",
                GetLastError());
            return FALSE;
        }

        s_fServiceWasRunning = fRunning;

        if (!fRunning)
        {
            if (!StartServiceA(s_hService, 0U, NULL))
            {
                unError = GetLastError();
                if (ERROR_SERVICE_ALREADY_RUNNING != unError)
                {
                    LOGGING_WRITE_LEVEL1_FMT(
                        L"StartService failed for existing TVICPORT service (Win32 error %u).",
                        unError);
                    return FALSE;
                }
            }

            s_fServiceStartedByUs = TRUE;
            IGNORE_RETURN_VALUE(
                DeviceAccess_WaitForServiceState(
                    s_hService,
                    SERVICE_RUNNING,
                    5000U));
        }
    }
    else
    {
        unError = GetLastError();
        if (ERROR_SERVICE_DOES_NOT_EXIST != unError)
        {
            LOGGING_WRITE_LEVEL1_FMT(
                L"OpenService failed for TVICPORT (Win32 error %u).",
                unError);
            return FALSE;
        }

        if (!DeviceAccess_BuildDriverPath(szDriverPath, RG_LEN(szDriverPath)))
        {
            LOGGING_WRITE_LEVEL1(L"Could not determine the bundled TVicPort.sys path.");
            return FALSE;
        }

        s_hService = CreateServiceA(
            s_hScm,
            TVIC_SERVICE_NAME_A,
            TVIC_SERVICE_NAME_A,
            SERVICE_START | SERVICE_STOP | SERVICE_QUERY_STATUS | DELETE,
            SERVICE_KERNEL_DRIVER,
            SERVICE_DEMAND_START,
            SERVICE_ERROR_NORMAL,
            szDriverPath,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL);

        if (NULL == s_hService)
        {
            LOGGING_WRITE_LEVEL1_FMT(
                L"CreateService failed for TVICPORT (Win32 error %u).",
                GetLastError());
            return FALSE;
        }

        s_fServiceCreatedByUs = TRUE;
        s_fServiceWasRunning = FALSE;

        if (!StartServiceA(s_hService, 0U, NULL))
        {
            unError = GetLastError();
            if (ERROR_SERVICE_ALREADY_RUNNING != unError)
            {
                LOGGING_WRITE_LEVEL1_FMT(
                    L"StartService failed for newly-created TVICPORT service (Win32 error %u).",
                    unError);
                return FALSE;
            }
        }

        s_fServiceStartedByUs = TRUE;
        IGNORE_RETURN_VALUE(
            DeviceAccess_WaitForServiceState(
                s_hService,
                SERVICE_RUNNING,
                5000U));
    }

    /*
     * The old updater opens \\.\TVicPortDevice0 after starting the service.
     * Give DriverEntry / symbolic-link creation a short bounded window.
     */
    {
        DWORD unTry = 0U;
        for (unTry = 0U; unTry < 50U; unTry++)
        {
            if (DeviceAccess_OpenDevice())
                return TRUE;
            Sleep(100U);
        }
    }

    LOGGING_WRITE_LEVEL1_FMT(
        L"Could not open \\\\.\\TVicPortDevice0 after starting TVICPORT (Win32 error %u).",
        GetLastError());

    return FALSE;
}

static void
DeviceAccess_RestoreServiceState(void)
{
    if (NULL != s_hService &&
        s_fServiceStartedByUs &&
        !s_fServiceWasRunning)
    {
        SERVICE_STATUS status;
        ZeroMemory(&status, sizeof(status));

        if (ControlService(s_hService, SERVICE_CONTROL_STOP, &status))
        {
            IGNORE_RETURN_VALUE(
                DeviceAccess_WaitForServiceState(
                    s_hService,
                    SERVICE_STOPPED,
                    5000U));
        }
    }

    if (NULL != s_hService && s_fServiceCreatedByUs)
    {
        IGNORE_RETURN_VALUE(DeleteService(s_hService));
    }

    s_fServiceCreatedByUs = FALSE;
    s_fServiceStartedByUs = FALSE;
    s_fServiceWasRunning = FALSE;
}

static BOOL
DeviceAccess_MapTpmWindow(void)
{
    TVIC_MAP_REQUEST request;
    DWORD unMappedLow32 = 0U;
    DWORD unReturned = 0U;
    DWORD unIoctlError = ERROR_SUCCESS;
    BOOL fResult = FALSE;
    MEMORY_BASIC_INFORMATION mbi;
    SIZE_T unVirtualQuery = 0U;
    volatile BYTE bProbe = 0U;
    ULONG_PTR unFullPointer = 0U;

    ZeroMemory(&request, sizeof(request));
    ZeroMemory(&mbi, sizeof(mbi));

    request.InterfaceType = 1U;
    request.BusNumber = 0U;
    request.BusAddress = (ULONGLONG)TPM_DEFAULT_MEM_BASE;
    request.AddressSpace = 0U;
    request.Length = TPM_DEFAULT_MEM_SIZE;

    DeviceAccess_Diag(
        "MAP request: size=%u InterfaceType=%lu Bus=%lu BusAddress=0x%I64X AddressSpace=%lu Length=0x%lX",
        (unsigned int)sizeof(request),
        request.InterfaceType,
        request.BusNumber,
        request.BusAddress,
        request.AddressSpace,
        request.Length);

    SetLastError(ERROR_SUCCESS);
    fResult = DeviceIoControl(
        s_hDevice,
        TVIC_IOCTL_MAP_PHYSICAL,
        &request,
        (DWORD)sizeof(request),
        &unMappedLow32,
        (DWORD)sizeof(unMappedLow32),
        &unReturned,
        NULL);
    unIoctlError = GetLastError();

    DeviceAccess_Diag(
        "MAP IOCTL 0x%08lX: result=%u Win32=%lu bytesReturned=%lu returnedLow32=0x%08lX",
        (unsigned long)TVIC_IOCTL_MAP_PHYSICAL,
        (unsigned int)fResult,
        unIoctlError,
        unReturned,
        unMappedLow32);

    if (!fResult || unReturned < sizeof(unMappedLow32))
        return FALSE;

    if (unMappedLow32 < 0x64U || 0xFFFFFFFFU == unMappedLow32)
    {
        DeviceAccess_Diag(
            "Driver returned low-DWORD token 0x%08lX; refusing because the known-good updater also rejects values below 0x64/0xFFFFFFFF.",
            unMappedLow32);
        return FALSE;
    }

    s_dwDriverMappedToken = unMappedLow32;

    /*
     * TVicPort.sys x64 truncates its 64-bit ZwMapViewOfSection-adjusted pointer:
     *
     *     mov eax, DWORD PTR [BaseAddress]
     *     mov [output], eax
     *
     * Therefore the DWORD is not necessarily the complete x64 user pointer.
     * First check the zero-extended value. If it is not mapped, reconstruct
     * the unique full pointer by matching its low 32 bits against current
     * readable committed virtual regions.
     */
    unFullPointer = (ULONG_PTR)unMappedLow32;

    SetLastError(ERROR_SUCCESS);
    unVirtualQuery = VirtualQuery(
        (LPCVOID)unFullPointer,
        &mbi,
        sizeof(mbi));

    DeviceAccess_Diag(
        "VirtualQuery(zero-extended 0x%08lX): ret=%Iu Win32=%lu Base=%p AllocationBase=%p RegionSize=0x%Ix State=0x%lX Protect=0x%lX Type=0x%lX",
        unMappedLow32,
        unVirtualQuery,
        GetLastError(),
        mbi.BaseAddress,
        mbi.AllocationBase,
        mbi.RegionSize,
        mbi.State,
        mbi.Protect,
        mbi.Type);

    if (0U == unVirtualQuery ||
        !DeviceAccess_IsReadableCommittedRegion(&mbi) ||
        unFullPointer < (ULONG_PTR)mbi.BaseAddress ||
        unFullPointer >= ((ULONG_PTR)mbi.BaseAddress + (ULONG_PTR)mbi.RegionSize))
    {
        DeviceAccess_Diag(
            "Zero-extended driver value is not a readable committed mapping; attempting full x64 pointer reconstruction.");

        if (!DeviceAccess_ReconstructMappedPointer(
                unMappedLow32,
                &unFullPointer))
        {
            return FALSE;
        }

        ZeroMemory(&mbi, sizeof(mbi));
        unVirtualQuery = VirtualQuery(
            (LPCVOID)unFullPointer,
            &mbi,
            sizeof(mbi));

        if (0U == unVirtualQuery ||
            !DeviceAccess_IsReadableCommittedRegion(&mbi))
        {
            DeviceAccess_Diag(
                "Reconstructed pointer %p still does not describe a readable committed mapping.",
                (void*)unFullPointer);
            return FALSE;
        }
    }

    s_unMappedPointer = unFullPointer;

    __try
    {
        bProbe = *(volatile BYTE*)s_unMappedPointer;
        DeviceAccess_Diag(
            "First mapped-byte probe succeeded: fullAddress=%p lowDWORD=0x%08lX value=0x%02X",
            (void*)s_unMappedPointer,
            s_dwDriverMappedToken,
            (unsigned int)bProbe);
    }
    __except(EXCEPTION_EXECUTE_HANDLER)
    {
        DeviceAccess_Diag(
            "First mapped-byte probe trapped SEH exception 0x%08lX at fullAddress=%p.",
            (unsigned long)GetExceptionCode(),
            (void*)s_unMappedPointer);
        s_unMappedPointer = 0U;
        return FALSE;
    }

    return TRUE;
}

static void
DeviceAccess_UnmapTpmWindow(void)
{
    if (0U != s_dwDriverMappedToken &&
        0xFFFFFFFFU != s_dwDriverMappedToken &&
        INVALID_HANDLE_VALUE != s_hDevice)
    {
        /*
         * The old x64 updater passes the address of the same 32-bit value
         * returned by IOCTL 0x80002008 to IOCTL 0x8000200C with input length 4.
         * Preserve that exact driver contract even when V8.1.3 reconstructed
         * a separate full 64-bit pointer for user-mode dereference.
         */
        DWORD unToken = s_dwDriverMappedToken;
        DWORD unReturned = 0U;

        IGNORE_RETURN_VALUE(
            DeviceIoControl(
                s_hDevice,
                TVIC_IOCTL_UNMAP_PHYSICAL,
                &unToken,
                (DWORD)sizeof(unToken),
                NULL,
                0U,
                &unReturned,
                NULL));
    }

    s_unMappedPointer = 0U;
    s_dwDriverMappedToken = 0U;
}

_Check_return_
unsigned int
DeviceAccess_Initialize(
    _In_ BYTE PbLocality)
{
    unsigned int unReturnValue = RC_E_FAIL;

    UNREFERENCED_PARAMETER(PbLocality);

    do
    {
        if (INVALID_HANDLE_VALUE != s_hDevice &&
            0U != s_unMappedPointer &&
            0U != s_dwDriverMappedToken &&
            0xFFFFFFFFU != s_dwDriverMappedToken)
        {
            unReturnValue = RC_SUCCESS;
            break;
        }

        /*
         * Serialize instances of this direct-access implementation.  This
         * cannot coordinate with Windows TBS, but prevents two copies of this
         * updater from driving the legacy physical-memory bridge at once.
         */
        s_hInstanceMutex = CreateMutexA(
            NULL,
            FALSE,
            "Global\\IFX_TPMFactoryUpd_V8_TVicPort_DirectAccess");

        if (NULL == s_hInstanceMutex)
        {
            LOGGING_WRITE_LEVEL1_FMT(
                L"CreateMutex failed for direct TPM access (Win32 error %u).",
                GetLastError());
            unReturnValue = RC_E_TPM_ACCESS_DENIED;
            break;
        }

        if (WAIT_OBJECT_0 != WaitForSingleObject(s_hInstanceMutex, 10000U))
        {
            LOGGING_WRITE_LEVEL1(L"Another V8 direct TPM access instance is active.");
            unReturnValue = RC_E_TPM_ACCESS_DENIED;
            break;
        }

        if (!DeviceAccess_EnsureDriverRunning())
        {
            unReturnValue = RC_E_TPM_ACCESS_DENIED;
            break;
        }

        if (!DeviceAccess_MapTpmWindow())
        {
            unReturnValue = RC_E_TPM_ACCESS_DENIED;
            break;
        }

        unReturnValue = RC_SUCCESS;
    }
    WHILE_FALSE_END;

    if (RC_SUCCESS != unReturnValue)
    {
        DeviceAccess_UnmapTpmWindow();

        if (INVALID_HANDLE_VALUE != s_hDevice)
        {
            CloseHandle(s_hDevice);
            s_hDevice = INVALID_HANDLE_VALUE;
        }

        DeviceAccess_RestoreServiceState();
        DeviceAccess_CloseServiceHandles();

        if (NULL != s_hInstanceMutex)
        {
            ReleaseMutex(s_hInstanceMutex);
            CloseHandle(s_hInstanceMutex);
            s_hInstanceMutex = NULL;
        }
    }

    return unReturnValue;
}

_Check_return_
unsigned int
DeviceAccess_Uninitialize(
    _In_ BYTE PbLocality)
{
    UNREFERENCED_PARAMETER(PbLocality);

    DeviceAccess_UnmapTpmWindow();

    if (INVALID_HANDLE_VALUE != s_hDevice)
    {
        CloseHandle(s_hDevice);
        s_hDevice = INVALID_HANDLE_VALUE;
    }

    DeviceAccess_RestoreServiceState();
    DeviceAccess_CloseServiceHandles();

    if (NULL != s_hInstanceMutex)
    {
        ReleaseMutex(s_hInstanceMutex);
        CloseHandle(s_hInstanceMutex);
        s_hInstanceMutex = NULL;
    }

    return RC_SUCCESS;
}

_Check_return_
BYTE
DeviceAccess_ReadByte(
    _In_ unsigned int PunMemoryAddress)
{
    volatile BYTE* pbAddress = NULL;
    BYTE bValue = 0U;

    if (!DeviceAccess_IsAddressValid(PunMemoryAddress, 1U) ||
        0U == s_unMappedPointer ||
        s_dwDriverMappedToken < 0x64U ||
        0xFFFFFFFFU == s_dwDriverMappedToken)
    {
        return 0U;
    }

    pbAddress = (volatile BYTE*)(
        s_unMappedPointer +
        (ULONG_PTR)(PunMemoryAddress - TPM_DEFAULT_MEM_BASE));

    __try
    {
        bValue = *pbAddress;
    }
    __except(EXCEPTION_EXECUTE_HANDLER)
    {
        DeviceAccess_Diag(
            "ReadByte trapped exception 0x%08lX: phys=0x%08X mapped=%p",
            (unsigned long)GetExceptionCode(),
            PunMemoryAddress,
            (void*)pbAddress);
        return 0U;
    }

    return bValue;
}
void
DeviceAccess_WriteByte(
    _In_ unsigned int PunMemoryAddress,
    _In_ BYTE PbData)
{
    volatile BYTE* pbAddress = NULL;

    if (!DeviceAccess_IsAddressValid(PunMemoryAddress, 1U) ||
        0U == s_unMappedPointer ||
        s_dwDriverMappedToken < 0x64U ||
        0xFFFFFFFFU == s_dwDriverMappedToken)
    {
        return;
    }

    pbAddress = (volatile BYTE*)(
        s_unMappedPointer +
        (ULONG_PTR)(PunMemoryAddress - TPM_DEFAULT_MEM_BASE));

    __try
    {
        *pbAddress = PbData;
    }
    __except(EXCEPTION_EXECUTE_HANDLER)
    {
        DeviceAccess_Diag(
            "WriteByte trapped exception 0x%08lX: phys=0x%08X mapped=%p value=0x%02X",
            (unsigned long)GetExceptionCode(),
            PunMemoryAddress,
            (void*)pbAddress,
            (unsigned int)PbData);
    }
}

_Check_return_
unsigned short
DeviceAccess_ReadWord(
    _In_ unsigned int PunMemoryAddress)
{
    volatile unsigned short* pusAddress = NULL;
    unsigned short usValue = 0U;

    if (!DeviceAccess_IsAddressValid(PunMemoryAddress, 2U) ||
        0U == s_unMappedPointer ||
        s_dwDriverMappedToken < 0x64U ||
        0xFFFFFFFFU == s_dwDriverMappedToken)
    {
        return 0U;
    }

    pusAddress = (volatile unsigned short*)(
        s_unMappedPointer +
        (ULONG_PTR)(PunMemoryAddress - TPM_DEFAULT_MEM_BASE));

    __try
    {
        usValue = *pusAddress;
    }
    __except(EXCEPTION_EXECUTE_HANDLER)
    {
        DeviceAccess_Diag(
            "ReadWord trapped exception 0x%08lX: phys=0x%08X mapped=%p",
            (unsigned long)GetExceptionCode(),
            PunMemoryAddress,
            (void*)pusAddress);
        return 0U;
    }

    return usValue;
}
void
DeviceAccess_WriteWord(
    _In_ unsigned int PunMemoryAddress,
    _In_ unsigned short PusData)
{
    volatile unsigned short* pusAddress = NULL;

    if (!DeviceAccess_IsAddressValid(PunMemoryAddress, 2U) ||
        0U == s_unMappedPointer ||
        s_dwDriverMappedToken < 0x64U ||
        0xFFFFFFFFU == s_dwDriverMappedToken)
    {
        return;
    }

    pusAddress = (volatile unsigned short*)(
        s_unMappedPointer +
        (ULONG_PTR)(PunMemoryAddress - TPM_DEFAULT_MEM_BASE));

    __try
    {
        *pusAddress = PusData;
    }
    __except(EXCEPTION_EXECUTE_HANDLER)
    {
        DeviceAccess_Diag(
            "WriteWord trapped exception 0x%08lX: phys=0x%08X mapped=%p value=0x%04X",
            (unsigned long)GetExceptionCode(),
            PunMemoryAddress,
            (void*)pusAddress,
            (unsigned int)PusData);
    }
}
