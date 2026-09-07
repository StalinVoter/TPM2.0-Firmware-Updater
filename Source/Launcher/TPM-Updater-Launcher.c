#define UNICODE
#define _UNICODE

#include <windows.h>
#include <wchar.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

static int AppendText(wchar_t *buffer, size_t capacity, size_t *length, const wchar_t *text)
{
    size_t count = wcslen(text);
    if (*length + count + 1 > capacity) {
        return 0;
    }
    memcpy(buffer + *length, text, count * sizeof(wchar_t));
    *length += count;
    buffer[*length] = L'\0';
    return 1;
}

/* Apply the quoting rules used by CommandLineToArgvW. */
static int AppendQuotedArgument(wchar_t *buffer, size_t capacity, size_t *length, const wchar_t *argument)
{
    const wchar_t *cursor;
    size_t backslashes = 0;

    if (!AppendText(buffer, capacity, length, (*length == 0) ? L"\"" : L" \"")) {
        return 0;
    }

    for (cursor = argument; ; ++cursor) {
        wchar_t ch = *cursor;
        if (ch == L'\\') {
            ++backslashes;
            continue;
        }

        if (ch == L'\"') {
            while (backslashes > 0) {
                if (!AppendText(buffer, capacity, length, L"\\\\")) return 0;
                --backslashes;
            }
            backslashes = 0;
            if (!AppendText(buffer, capacity, length, L"\\\"")) return 0;
            continue;
        }

        if (ch == L'\0') {
            while (backslashes > 0) {
                if (!AppendText(buffer, capacity, length, L"\\\\")) return 0;
                --backslashes;
            }
            return AppendText(buffer, capacity, length, L"\"");
        }

        while (backslashes > 0) {
            if (!AppendText(buffer, capacity, length, L"\\")) return 0;
            --backslashes;
        }
        backslashes = 0;

        {
            wchar_t one[2] = { ch, L'\0' };
            if (!AppendText(buffer, capacity, length, one)) return 0;
        }
    }
}

static void PrintLaunchError(const wchar_t *message, DWORD errorCode)
{
    fwprintf(stderr, L"\n%s\nWindows error: %lu\n", message, (unsigned long)errorCode);
}

int wmain(int argc, wchar_t **argv)
{
    wchar_t modulePath[32768];
    wchar_t packageDirectory[32768];
    wchar_t powershellPath[32768];
    wchar_t systemDirectory[32768];
    wchar_t scriptPath[32768];
    wchar_t *commandLine;
    size_t commandCapacity = 65536;
    size_t commandLength = 0;
    DWORD pathLength;
    int index;
    STARTUPINFOW startupInfo;
    PROCESS_INFORMATION processInfo;
    DWORD childExitCode = 1;

    pathLength = GetModuleFileNameW(NULL, modulePath, ARRAYSIZE(modulePath));
    if (pathLength == 0 || pathLength >= ARRAYSIZE(modulePath)) {
        PrintLaunchError(L"The updater could not determine its own location.", GetLastError());
        return 80;
    }

    wcscpy_s(packageDirectory, ARRAYSIZE(packageDirectory), modulePath);
    {
        wchar_t *slash = wcsrchr(packageDirectory, L'\\');
        if (slash == NULL) {
            fwprintf(stderr, L"\nThe updater must be run from its portable folder.\n");
            return 81;
        }
        *slash = L'\0';
    }

    if (GetSystemDirectoryW(systemDirectory, ARRAYSIZE(systemDirectory)) == 0) {
        PrintLaunchError(L"The updater could not locate Windows PowerShell.", GetLastError());
        return 82;
    }

    if (swprintf_s(powershellPath, ARRAYSIZE(powershellPath),
                   L"%s\\WindowsPowerShell\\v1.0\\powershell.exe", systemDirectory) < 0 ||
        swprintf_s(scriptPath, ARRAYSIZE(scriptPath),
                   L"%s\\TPM-Updater.ps1", packageDirectory) < 0) {
        fwprintf(stderr, L"\nThe portable-folder path is too long.\n");
        return 83;
    }

    if (GetFileAttributesW(powershellPath) == INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(scriptPath) == INVALID_FILE_ATTRIBUTES) {
        fwprintf(stderr, L"\nThe portable updater is incomplete. Run VERIFY-PORTABLE.cmd.\n");
        return 84;
    }

    commandLine = (wchar_t *)calloc(commandCapacity, sizeof(wchar_t));
    if (commandLine == NULL) {
        fwprintf(stderr, L"\nThe updater could not allocate its command line.\n");
        return 85;
    }

    if (!AppendQuotedArgument(commandLine, commandCapacity, &commandLength, powershellPath) ||
        !AppendText(commandLine, commandCapacity, &commandLength,
                    L" -NoLogo -NoProfile -ExecutionPolicy Bypass -File") ||
        !AppendQuotedArgument(commandLine, commandCapacity, &commandLength, scriptPath)) {
        free(commandLine);
        fwprintf(stderr, L"\nThe updater command line is too long.\n");
        return 86;
    }

    for (index = 1; index < argc; ++index) {
        if (!AppendQuotedArgument(commandLine, commandCapacity, &commandLength, argv[index])) {
            free(commandLine);
            fwprintf(stderr, L"\nThe updater command line is too long.\n");
            return 86;
        }
    }

    ZeroMemory(&startupInfo, sizeof(startupInfo));
    startupInfo.cb = sizeof(startupInfo);
    ZeroMemory(&processInfo, sizeof(processInfo));

    if (!SetCurrentDirectoryW(packageDirectory)) {
        DWORD errorCode = GetLastError();
        free(commandLine);
        PrintLaunchError(L"The updater could not open its portable folder.", errorCode);
        return 87;
    }

    if (!CreateProcessW(powershellPath, commandLine, NULL, NULL, TRUE, 0, NULL,
                        packageDirectory, &startupInfo, &processInfo)) {
        DWORD errorCode = GetLastError();
        free(commandLine);
        PrintLaunchError(L"The updater could not start its user interface.", errorCode);
        return 88;
    }

    free(commandLine);
    CloseHandle(processInfo.hThread);
    WaitForSingleObject(processInfo.hProcess, INFINITE);
    if (!GetExitCodeProcess(processInfo.hProcess, &childExitCode)) {
        childExitCode = 89;
    }
    CloseHandle(processInfo.hProcess);
    return (int)childExitCode;
}
