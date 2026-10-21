@echo off
rem ============================================================
rem check_debug.bat - Launcher only.
rem Core pre-debug check logic lives in check_debug.ps1
rem (PowerShell implementation, same logic as check_debug.py):
rem   - Rule 1: total FLASH / total RAM must be STRICTLY LESS than
rem     the chip max in mcu_isa.json (parsed from link.ld MEMORY block).
rem   - Rule 2: --ram-avail <value> from the current hardware config;
rem     total RAM <= that value.
rem   - Rule 3: FLASH ORIGIN != 0 detected and reported as WARN
rem     (the skill must ask the user about a program at address 0).
rem   - Breakpoints: maxbreakpoint from mcu_isa.json (empty = no limit);
rem     --breakpoints <n> hard-checks the limit.
rem   - PowerShell reads/writes UTF-8 natively and accepts forward-slash
rem     paths (no findstr / GBK / path issues from Git Bash / opencode).
rem Exit codes: 0 = PASS; 1 = FAIL; 2 = FATAL.
rem Usage:
rem   check_debug.bat <link.ld> [link.ld2] --chip CH32H417WEU [--core v3f|v5f|single|auto] [--ram-avail 896K] [--breakpoints 3] [--quiet]
rem ============================================================
setlocal
set "PS1=%~dp0check_debug.ps1"
if not exist "%PS1%" ( echo [FATAL] check_debug.ps1 not found: "%PS1%" & exit /b 2 )

rem ---- self-heal: ensure the .ps1 is UTF-8 with BOM. Windows PowerShell 5.1 reads
rem       no-BOM files as ANSI, so Chinese/emoji become mojibake and the script can
rem       fail to parse. Re-add the BOM if any edit dropped it. Keep this .bat ASCII. ----
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p='%~dp0check_debug.ps1'; $b=[IO.File]::ReadAllBytes($p); if(-not($b.Length-ge 3 -and $b[0]-eq 0xEF -and $b[1]-eq 0xBB -and $b[2]-eq 0xBF)){ $t=[IO.File]::ReadAllText($p,[Text.Encoding]::UTF8); [IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding($true))) }"

rem Prefer bundled Windows PowerShell 5.1; fall back to pwsh (PowerShell 7).
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%PS_EXE%" goto runPS51
where pwsh.exe >nul 2>nul
if not errorlevel 1 goto runPwsh7
echo [FATAL] PowerShell not found ^(powershell.exe / pwsh.exe^)
exit /b 2

:runPS51
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
exit /b %ERRORLEVEL%

:runPwsh7
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
exit /b %ERRORLEVEL%
