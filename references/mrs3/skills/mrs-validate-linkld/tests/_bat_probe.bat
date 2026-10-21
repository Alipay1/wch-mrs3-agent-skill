@echo off
setlocal enabledelayedexpansion
set "CLEAN=%TEMP%\probe_clean3.txt"
rem write a minimal clean file inline
> "%CLEAN%" (
echo MEMORY
echo {
echo FLASH rx : ORIGIN = 0x40000000, LENGTH = 480K
echo RAM xrw : ORIGIN = 0x38000000, LENGTH = 448K
echo }
echo _estack = ORIGIN + LENGTH;
)
set "seenMEM=0"
set "INMEM=0"
set "memdepth=0"
set "MEM_START=0"
set "MEM_END=0"
for /f "tokens=1,* delims=:" %%A in ('findstr /n "^" "%CLEAN%"') do (
    set "lineno=%%A"
    set "t=%%B"
    call :trim t
    if "!INMEM!"=="0" (
        set "t6=!t:~0,6!"
        if /i "!t6!"=="MEMORY" set "seenMEM=1"
        set "chk=!t:{=!"
        if not "!chk!"=="!t!" if "!seenMEM!"=="1" (
            set "INMEM=1" & set "MEM_START=!lineno!"
            set "S=!t!" & call :strLen & set /a "d=!LEN!"
            set "S=!t:{=!" & call :strLen & set /a "o=!d!-!LEN!"
            set "S=!t:}=!" & call :strLen & set /a "c=!d!-!LEN!"
            set /a "memdepth=!o!-!c!"
            if !memdepth! LEQ 0 ( set "INMEM=0" & set "MEM_END=!lineno!" )
        )
    ) else (
        set "S=!t!" & call :strLen & set /a "d=!LEN!"
        set "S=!t:{=!" & call :strLen & set /a "o=!d!-!LEN!"
        set "S=!t:}=!" & call :strLen & set /a "c=!d!-!LEN!"
        set /a memdepth+=!o!-!c!
        if !memdepth! LEQ 0 ( set "INMEM=0" & set "MEM_END=!lineno!" )
    )
    echo line !lineno!: INMEM=[!INMEM!] memdepth=[!memdepth!] t=[!t!]
)
del "%CLEAN%" 2>nul
exit /b 0

:trim
set "STR=!%~1!"
:trimLoop
if not defined STR goto trimDone
if "!STR:~0,1!"==" " ( set "STR=!STR:~1!" & goto trimLoop )
if "!STR:~-1!"==" " ( set "STR=!STR:~0,-1!" & goto trimLoop )
:trimDone
set "%~1=!STR!"
exit /b 0

:strLen
set "_st=!S!"
set "LEN=0"
:strLenLoop
if not defined _st goto strLenDone
set "_st=!_st:~1!"
set /a LEN+=1
goto strLenLoop
:strLenDone
exit /b 0
