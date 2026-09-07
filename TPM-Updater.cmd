@echo off
setlocal EnableExtensions
cd /d "%~dp0"

if exist "%~dp0TPM-Updater.exe" (
  "%~dp0TPM-Updater.exe" %*
  exit /b %ERRORLEVEL%
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp000-PowerShell-Syntax-Check.ps1"
if errorlevel 1 (
  echo.
  echo PowerShell syntax check failed.
  pause
  exit /b 91
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0TPM-Updater.ps1" %*
exit /b %ERRORLEVEL%
