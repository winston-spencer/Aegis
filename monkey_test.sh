#!/bin/bash

PACKAGE="com.beemdevelopment.aegis.debug"
LOG_DIR="monkey_logs"

mkdir -p "$LOG_DIR"

echo "Building debug APK..."
./gradlew assembleDebug
if [ $? -ne 0 ]; then
    echo "Build failed. Exiting."
    exit 1
fi
echo "Build complete."

echo "Installing debug APK..."
adb install -r app/build/outputs/apk/debug/app-debug.apk
if [ $? -ne 0 ]; then
    echo "Install failed. Exiting."
    exit 1
fi
echo "Install complete."

echo "Launching app..."
adb shell am start -n com.beemdevelopment.aegis.debug/com.beemdevelopment.aegis.ui.MainActivity
sleep 2

echo "Starting Monkey Test Suite for $PACKAGE"
echo "Logs will be saved to $LOG_DIR/"
echo "========================================"

run_monkey() {
    local run_num=$1
    local description=$2
    shift 2
    local log_file="$LOG_DIR/monkey_run${run_num}.txt"

    echo "[$run_num/10] $description..."
    echo "Command: adb shell monkey $@" > "$log_file"
    echo "Description: $description" >> "$log_file"
    echo "Started: $(date)" >> "$log_file"
    echo "========================================" >> "$log_file"

    adb shell monkey "$@" >> "$log_file" 2>&1

    if grep -q "Monkey finished" "$log_file"; then
        echo "       PASSED - Log: $log_file"
    else
        echo "       FAILED - Log: $log_file"
    fi

    echo "Finished: $(date)" >> "$log_file"
}

run_monkey 1 "Baseline touch-heavy" \
    -p "$PACKAGE" -s 1902834875253 --pct-touch 70 --pct-motion 10 -v 5000

run_monkey 2 "Navigation focused" \
    -p "$PACKAGE" -s 2845619073821 --pct-nav 50 --pct-majornav 25 -v 5000

run_monkey 3 "High event count throttled" \
    -p "$PACKAGE" -s 3719284056132 --throttle 200 -v 50000

run_monkey 4 "Ignore crashes keep running" \
    -p "$PACKAGE" -s 4521873946201 --ignore-crashes --ignore-timeouts -v 5000

run_monkey 5 "System keys heavy" \
    -p "$PACKAGE" -s 5634902817345 --pct-syskeys 40 --pct-touch 30 -v 5000

run_monkey 6 "Pinch zoom focus" \
    -p "$PACKAGE" -s 6748291035467 --pct-pinchzoom 30 --pct-touch 40 -v 5000

run_monkey 7 "Fast stress test" \
    -p "$PACKAGE" -s 7856134920578 --pct-touch 50 --pct-motion 20 -v 50000

run_monkey 8 "App switch heavy" \
    -p "$PACKAGE" -s 8923047165689 --pct-appswitch 30 --pct-touch 40 -v 5000

run_monkey 9 "Slow realistic user simulation" \
    -p "$PACKAGE" -s 9034158276790 --throttle 500 --pct-touch 60 --pct-nav 20 -v 5000

run_monkey 10 "Full fault tolerance" \
    -p "$PACKAGE" -s 1234567890123 --ignore-crashes --ignore-timeouts \
    --ignore-security-exceptions --monitor-native-crashes -v 5000

echo ""
echo "========================================"
echo "All runs complete. Results in $LOG_DIR/"
echo ""
echo "Summary:"
for i in $(seq 1 10); do
    log="$LOG_DIR/monkey_run${i}.txt"
    if grep -q "Monkey finished" "$log"; then
        echo "  Run $i: PASSED"
    else
        echo "  Run $i: FAILED"
    fi
done