@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WheelSetup.ps1" %*
set "setupExit=%ERRORLEVEL%"
pause
exit /b %setupExit%
