@echo off
rem mtb for Windows: runs windows\mtb.ps1 with PowerShell 7 (pwsh) when it is installed, else the Windows PowerShell
rem that comes with Windows, whatever the execution policy. See mtb help.
setlocal
set "PS_EXE=powershell.exe"
where pwsh.exe >nul 2>nul && set "PS_EXE=pwsh.exe"
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\windows\mtb.ps1" %*
exit /b %ERRORLEVEL%
