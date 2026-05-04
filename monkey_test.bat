@echo off
setlocal enabledelayedexpansion

set PACKAGE=com.beemdevelopment.aegis.debug
set LOG_DIR=monkey_logs
set RUN_FILTER=all
set RUNS_EXECUTED=
set DEVICE=
set ADB=adb

:: Parse arguments
:parse_args
if "%~1"=="" goto :done_args
if "%~1"=="--run" (
    set RUN_FILTER=%~2
    shift
    shift
    goto :parse_args
)
if "%~1"=="--device" (
    set DEVICE=%~2
    shift
    shift
    goto :parse_args
)
if "%~1"=="--list-devices" (
    echo Connected devices:
    adb devices -l
    exit /b 0
)
if "%~1"=="--help" (
    echo Usage: %~nx0 [--run ^<N^|all^>] [--device ^<serial^>] [--list-devices]
    echo.
    echo Options:
    echo   --run ^<N^>          Run only iteration N (1-10)
    echo   --run all          Run all 10 iterations (default)
    echo   --device ^<serial^>  Target a specific device (use --list-devices to find serial)
    echo   --list-devices     List all connected devices and exit
    echo   --help             Show this help message
    exit /b 0
)
echo Unknown option: %~1
echo Use --help for usage information.
exit /b 1
:done_args

:: Set up adb command with device targeting
if not "%DEVICE%"=="" (
    set ADB=adb -s %DEVICE%
)

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

echo Building debug APK...
call gradlew.bat assembleDebug
if %ERRORLEVEL% neq 0 (
    echo Build failed. Exiting.
    exit /b 1
)
echo Build complete.

echo Installing debug APK...
echo   Using: !ADB! install -r app\build\outputs\apk\debug\app-debug.apk
!ADB! install -r app\build\outputs\apk\debug\app-debug.apk
if %ERRORLEVEL% neq 0 (
    echo Install failed. Exiting.
    echo Hint: use --list-devices to see connected devices, then --device ^<serial^> to target one.
    exit /b 1
)
echo Install complete.

echo Launching app...
!ADB! shell am start -n com.beemdevelopment.aegis.debug/com.beemdevelopment.aegis.ui.MainActivity
timeout /t 2 /nobreak >nul

echo Starting Monkey Test Suite for %PACKAGE%
if not "%DEVICE%"=="" (
    echo Target device: %DEVICE%
)
echo Logs will be saved to %LOG_DIR%\
echo ========================================

:: Define monkey args for each run
set "ARGS1=-p %PACKAGE% -s 1902834875253 --pct-touch 70 --pct-motion 10 -v 5000"
set "DESC1=Baseline touch-heavy"
set "ARGS2=-p %PACKAGE% -s 2845619073821 --pct-nav 50 --pct-majornav 25 -v 5000"
set "DESC2=Navigation focused"
set "ARGS3=-p %PACKAGE% -s 3719284056132 --throttle 200 -v 50000"
set "DESC3=High event count throttled"
set "ARGS4=-p %PACKAGE% -s 4521873946201 --ignore-crashes --ignore-timeouts -v 5000"
set "DESC4=Ignore crashes keep running"
set "ARGS5=-p %PACKAGE% -s 5634902817345 --pct-syskeys 40 --pct-touch 30 -v 5000"
set "DESC5=System keys heavy"
set "ARGS6=-p %PACKAGE% -s 6748291035467 --pct-pinchzoom 30 --pct-touch 40 -v 5000"
set "DESC6=Pinch zoom focus"
set "ARGS7=-p %PACKAGE% -s 7856134920578 --pct-touch 50 --pct-motion 20 -v 50000"
set "DESC7=Fast stress test"
set "ARGS8=-p %PACKAGE% -s 8923047165689 --pct-appswitch 30 --pct-touch 40 -v 5000"
set "DESC8=App switch heavy"
set "ARGS9=-p %PACKAGE% -s 9034158276790 --throttle 500 --pct-touch 60 --pct-nav 20 -v 5000"
set "DESC9=Slow realistic user simulation"
set "ARGS10=-p %PACKAGE% -s 1234567890123 --ignore-crashes --ignore-timeouts --ignore-security-exceptions --monitor-native-crashes -v 5000"
set "DESC10=Full fault tolerance"

set TOTAL=10

if "%RUN_FILTER%"=="all" (
    for /L %%i in (1,1,%TOTAL%) do (
        set "MONKEY_ARGS=!ARGS%%i!"
        set "MONKEY_DESC=!DESC%%i!"
        call :run_monkey %%i
    )
) else (
    if %RUN_FILTER% geq 1 if %RUN_FILTER% leq %TOTAL% (
        set "MONKEY_ARGS=!ARGS%RUN_FILTER%!"
        set "MONKEY_DESC=!DESC%RUN_FILTER%!"
        call :run_monkey %RUN_FILTER%
    ) else (
        echo Error: --run must be between 1 and %TOTAL%, or 'all'
        exit /b 1
    )
)

echo.
echo ========================================
echo Runs complete. Results in %LOG_DIR%\
echo.
echo Summary:
for %%i in (%RUNS_EXECUTED%) do (
    set "LOG=%LOG_DIR%\monkey_run%%i.txt"
    set /p CMD=<"!LOG!"
    set "CMD=!CMD:Command: =!"
    findstr /c:"Monkey finished" "!LOG!" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        echo   Run %%i: PASSED  ^| !CMD!
    ) else (
        echo   Run %%i: FAILED  ^| !CMD!
    )
)
goto :eof

:run_monkey
set RUN_NUM=%1
set LOG_FILE=%LOG_DIR%\monkey_run%RUN_NUM%.txt

echo [%RUN_NUM%/%TOTAL%] !MONKEY_DESC!
echo   Command: !ADB! shell monkey !MONKEY_ARGS!

echo Command: !ADB! shell monkey !MONKEY_ARGS! > "%LOG_FILE%"
echo Description: !MONKEY_DESC! >> "%LOG_FILE%"
echo Started: %DATE% %TIME% >> "%LOG_FILE%"
echo ======================================== >> "%LOG_FILE%"

!ADB! shell monkey !MONKEY_ARGS! >> "%LOG_FILE%" 2>&1

findstr /c:"Monkey finished" "%LOG_FILE%" >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo   PASSED - Log: %LOG_FILE%
) else (
    echo   FAILED - Log: %LOG_FILE%
)

echo Finished: %DATE% %TIME% >> "%LOG_FILE%"
set "RUNS_EXECUTED=!RUNS_EXECUTED! %RUN_NUM%"
goto :eof
