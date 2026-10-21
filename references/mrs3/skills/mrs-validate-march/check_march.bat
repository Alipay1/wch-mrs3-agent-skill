@echo off
rem ============================================================
rem check_march.bat - Launcher only.
rem Core validation logic lives in check_march.ps1
rem (PowerShell implementation, same logic as check_march.py):
rem   - PowerShell reads/writes UTF-8 natively and accepts
rem     forward-slash paths, so no findstr / GBK / path issues
rem     when invoked from Git Bash / opencode bash tools.
rem   - Arguments, output format and exit codes match the Python
rem     version: 0 = PASS; 1 = FAIL / argument error.
rem Usage:
rem   check_march.bat --chip CH32H417WEU [--core v3f|v5f] [--march <arch>] [--toolchain <tc>] [--abi <abi>] [--startfile-dir <dir>]
rem   check_march.bat --march <arch> --isa-ext i,m,a,c,xw
rem   check_march.bat --selftest
rem ============================================================
setlocal
set "PS1=%~dp0check_march.ps1"
if not exist "%PS1%" ( echo [FATAL] check_march.ps1 not found: "%PS1%" & exit /b 1 )

rem ---- self-heal: ensure the .ps1 is UTF-8 with BOM. Windows PowerShell 5.1 reads
rem       no-BOM files as ANSI, so Chinese/emoji become mojibake and the script can
rem       fail to parse. Re-add the BOM if any edit dropped it. Keep this .bat ASCII. ----
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p='%~dp0check_march.ps1'; $b=[IO.File]::ReadAllBytes($p); if(-not($b.Length-ge 3 -and $b[0]-eq 0xEF -and $b[1]-eq 0xBB -and $b[2]-eq 0xBF)){ $t=[IO.File]::ReadAllText($p,[Text.Encoding]::UTF8); [IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding($true))) }"

rem Prefer bundled Windows PowerShell 5.1; fall back to pwsh (PowerShell 7).
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%PS_EXE%" goto runPS51
where pwsh.exe >nul 2>nul
if not errorlevel 1 goto runPwsh7
echo [FATAL] PowerShell not found ^(powershell.exe / pwsh.exe^)
exit /b 1

:runPS51
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
exit /b %ERRORLEVEL%

:runPwsh7
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
exit /b %ERRORLEVEL%
