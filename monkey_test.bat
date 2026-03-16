@echo off
setlocal enabledelayedexpansion

set PACKAGE=com.beemdevelopment.aegis.debug
set LOG_DIR=monkey_logs

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

echo Building debug APK...
call gradlew.bat assembleDebug
if %ERRORLEVEL% neq 0 (
    echo Build failed. Exiting.
    exit /b 1
)
echo Build complete.

echo Installing debug APK...
adb install -r app\build\outputs\apk\debug\app-debug.apk
if %ERRORLEVEL% neq 0 (
    echo Install failed. Exiting.
    exit /b 1
)
echo Install complete.

echo Launching app...
adb shell am start -n com.beemdevelopment.aegis.debug/com.beemdevelopment.aegis.ui.MainActivity
timeout /t 2 /nobreak >nul

echo Starting Monkey Test Suite for %PACKAGE%
echo Logs will be saved to %LOG_DIR%\
echo ========================================

call :run_monkey 1  "Baseline touch-heavy"           -p %PACKAGE% -s 1902834875253 --pct-touch 70 --pct-motion 10 -v 5000
call :run_monkey 2  "Navigation focused"             -p %PACKAGE% -s 2845619073821 --pct-nav 50 --pct-majornav 25 -v 5000
call :run_monkey 3  "High event count throttled"     -p %PACKAGE% -s 3719284056132 --throttle 200 -v 50000
call :run_monkey 4  "Ignore crashes keep running"    -p %PACKAGE% -s 4521873946201 --ignore-crashes --ignore-timeouts -v 5000
call :run_monkey 5  "System keys heavy"              -p %PACKAGE% -s 5634902817345 --pct-syskeys 40 --pct-touch 30 -v 5000
call :run_monkey 6  "Pinch zoom focus"               -p %PACKAGE% -s 6748291035467 --pct-pinchzoom 30 --pct-touch 40 -v 5000
call :run_monkey 7  "Fast stress test"               -p %PACKAGE% -s 7856134920578 --pct-touch 50 --pct-motion 20 -v 50000
call :run_monkey 8  "App switch heavy"               -p %PACKAGE% -s 8923047165689 --pct-appswitch 30 --pct-touch 40 -v 5000
call :run_monkey 9  "Slow realistic user simulation" -p %PACKAGE% -s 9034158276790 --throttle 500 --pct-touch 60 --pct-nav 20 -v 5000
call :run_monkey 10 "Full fault tolerance"           -p %PACKAGE% -s 1234567890123 --ignore-crashes --ignore-timeouts --ignore-security-exceptions --monitor-native-crashes -v 5000

echo.
echo ========================================
echo All runs complete. Results in %LOG_DIR%\
echo.
echo Summary:
for /L %%i in (1,1,10) do (
    set LOG=%LOG_DIR%\monkey_run%%i.txt
    findstr /c:"Monkey finished" "!LOG!" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        echo   Run %%i: PASSED
    ) else (
        echo   Run %%i: FAILED
    )
)
goto :eof

:run_monkey
set RUN_NUM=%1
set DESCRIPTION=%2
set LOG_FILE=%LOG_DIR%\monkey_run%RUN_NUM%.txt
set MONKEY_ARGS=%3 %4 %5 %6 %7 %8 %9

echo [%RUN_NUM%/10] %DESCRIPTION%...
echo Command: adb shell monkey %MONKEY_ARGS% > "%LOG_FILE%"
echo Description: %DESCRIPTION% >> "%LOG_FILE%"
echo Started: %DATE% %TIME% >> "%LOG_FILE%"
echo ======================================== >> "%LOG_FILE%"

adb shell monkey %MONKEY_ARGS% >> "%LOG_FILE%" 2>&1

findstr /c:"Monkey finished" "%LOG_FILE%" >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo        PASSED - Log: %LOG_FILE%
) else (
    echo        FAILED - Log: %LOG_FILE%
)

echo Finished: %DATE% %TIME% >> "%LOG_FILE%"
goto :eof
