@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1" %*
set "setupExit=%ERRORLEVEL%"
pause
exit /b %setupExit%
