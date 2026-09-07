@echo off
setlocal EnableExtensions
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VERIFY-PORTABLE.ps1"
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" echo Portable dist verification FAILED.
pause
exit /b %RC%
