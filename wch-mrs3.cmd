@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\wch-mrs3.ps1" %*
exit /b %ERRORLEVEL%
