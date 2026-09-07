/** Windows 11 console backend for Infineon TPMFactoryUpd. */
#include "ConsoleIO.h"
#include <Windows.h>
#include <conio.h>
#include <stdio.h>

unsigned int g_unPageBreakCount = 0;
unsigned int g_unPageBreakMax = 25;

void ConsoleIO_InitConsole(_In_ unsigned int PunMode)
{
    CONSOLE_SCREEN_BUFFER_INFO info;
    HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);

    if (CONSOLE_BUFFER_BIG == PunMode && INVALID_HANDLE_VALUE != hOut)
    {
        COORD size;
        size.X = SCREEN_BUFFER_SIZE_X;
        size.Y = SCREEN_BUFFER_SIZE_Y;
        SetConsoleScreenBufferSize(hOut, size);
    }

    if (INVALID_HANDLE_VALUE != hOut && GetConsoleScreenBufferInfo(hOut, &info))
    {
        SHORT rows = (SHORT)(info.srWindow.Bottom - info.srWindow.Top + 1);
        if (rows > 5)
            g_unPageBreakMax = (unsigned int)rows;
    }

    /* Make redirected text output deterministic on current Windows consoles. */
    SetConsoleOutputCP(CP_UTF8);
}

void ConsoleIO_SetInteractiveMode(void)
{
    /* _getwch() already reads a key without echo. */
}

void ConsoleIO_UnInitConsole(void)
{
}

_Check_return_
unsigned int ConsoleIO_ClearScreen(void)
{
    HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    DWORD count;
    DWORD cells;
    COORD home = {0, 0};

    if (INVALID_HANDLE_VALUE == hOut || !GetConsoleScreenBufferInfo(hOut, &csbi))
        return RC_E_FAIL;

    cells = (DWORD)csbi.dwSize.X * (DWORD)csbi.dwSize.Y;
    if (!FillConsoleOutputCharacterW(hOut, L' ', cells, home, &count))
        return RC_E_FAIL;
    if (!FillConsoleOutputAttribute(hOut, csbi.wAttributes, cells, home, &count))
        return RC_E_FAIL;
    if (!SetConsoleCursorPosition(hOut, home))
        return RC_E_FAIL;

    g_unPageBreakCount = 0;
    return RC_SUCCESS;
}

_Check_return_
int ConsoleIO_KeyboardHit(void)
{
    return _kbhit();
}

_Check_return_
wchar_t ConsoleIO_ReadWChar(void)
{
    wint_t ch = _getwch();
    /* Consume the second byte/code for Windows extended key sequences. */
    if (0 == ch || 0xE0 == ch)
    {
        (void)_getwch();
        return (wchar_t)WEOF;
    }
    return (wchar_t)ch;
}

_Check_return_
unsigned int ConsoleIO_WritePlatformV(
    _In_ BOOL PfNewLine,
    _In_z_ const wchar_t* PwszFormat,
    _In_ va_list PargList)
{
    wchar_t wszBuf[PRINT_BUFFER_SIZE];
    int nWritten;

    if (NULL == PwszFormat)
        return RC_E_BAD_PARAMETER;

    ZeroMemory(wszBuf, sizeof(wszBuf));
    nWritten = _vsnwprintf_s(wszBuf, RG_LEN(wszBuf), _TRUNCATE, PwszFormat, PargList);
    if (nWritten < 0)
    {
        fputws(wszBuf, stdout);
        if (PfNewLine)
            fputws(L"\n", stdout);
        fflush(stdout);
        return RC_E_BUFFER_TOO_SMALL;
    }

    fputws(wszBuf, stdout);
    if (PfNewLine)
        fputws(L"\n", stdout);
    fflush(stdout);
    return RC_SUCCESS;
}
