#!/bin/bash

PACKAGE="com.beemdevelopment.aegis.debug"
LOG_DIR="monkey_logs"
RUN_FILTER="all"
DEVICE=""
ADB="adb"
RESTORE_SNAPSHOT=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --run)
            RUN_FILTER="$2"
            shift 2
            ;;
        --device)
            DEVICE="$2"
            shift 2
            ;;
        --list-devices)
            echo "Connected devices:"
            adb devices -l
            exit 0
            ;;
        --list-snapshots)
            if [ -z "$DEVICE" ]; then
                echo "Error: --list-snapshots requires --device <serial>"
                echo "Use --list-devices to find your emulator serial."
                exit 1
            fi
            echo "Snapshots for device $DEVICE:"
            adb -s "$DEVICE" emu avd snapshot list
            exit 0
            ;;
        --restore-snapshot)
            RESTORE_SNAPSHOT=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --run <N>          Run only iteration N (1-10)"
            echo "  --run all          Run all 10 iterations (default)"
            echo "  --device <serial>  Target a specific device (use --list-devices to find serial)"
            echo "  --list-devices     List all connected devices and exit"
            echo "  --list-snapshots   List snapshots for the device (requires --device)"
            echo "  --restore-snapshot Restore the most recent snapshot before running tests"
            echo "  --help             Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --list-devices"
            echo "  $0 --device emulator-5554 --list-snapshots"
            echo "  $0 --device emulator-5554 --restore-snapshot --run 1"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# Set up adb command with device targeting
if [ -n "$DEVICE" ]; then
    ADB="adb -s $DEVICE"
fi

# Restore most recent snapshot if requested
if [ "$RESTORE_SNAPSHOT" = true ]; then
    if [ -z "$DEVICE" ]; then
        echo "Error: --restore-snapshot requires --device <serial>"
        exit 1
    fi
    echo "Fetching snapshot list for $DEVICE..."
    SNAPSHOT_LIST=$($ADB emu avd snapshot list 2>&1)
    echo "$SNAPSHOT_LIST"

    # Parse the last snapshot name (skip header/OK lines)
    LATEST_SNAPSHOT=$(echo "$SNAPSHOT_LIST" | grep -v -E "^OK$|^$|Snapshot|List" | tail -1 | awk '{print $1}')

    if [ -z "$LATEST_SNAPSHOT" ]; then
        echo "Error: No snapshots found for device $DEVICE"
        exit 1
    fi

    echo "Restoring snapshot: $LATEST_SNAPSHOT"
    $ADB emu avd snapshot load "$LATEST_SNAPSHOT"
    if [ $? -ne 0 ]; then
        echo "Snapshot restore failed. Exiting."
        exit 1
    fi
    echo "Snapshot restored. Waiting for device..."
    sleep 3
fi

mkdir -p "$LOG_DIR"

echo "Building debug APK..."
./gradlew assembleDebug
if [ $? -ne 0 ]; then
    echo "Build failed. Exiting."
    exit 1
fi
echo "Build complete."

echo "Installing debug APK..."
echo "  Using: $ADB install -r app/build/outputs/apk/debug/app-debug.apk"
$ADB install -r app/build/outputs/apk/debug/app-debug.apk
if [ $? -ne 0 ]; then
    echo "Install failed. Exiting."
    echo "Hint: use --list-devices to see connected devices, then --device <serial> to target one."
    exit 1
fi
echo "Install complete."

echo "Launching app..."
$ADB shell am start -n com.beemdevelopment.aegis.debug/com.beemdevelopment.aegis.ui.MainActivity
sleep 2

echo "Starting Monkey Test Suite for $PACKAGE"
if [ -n "$DEVICE" ]; then
    echo "Target device: $DEVICE"
fi
echo "Logs will be saved to $LOG_DIR/"
echo "========================================"

# Store descriptions and monkey args for each run
DESCRIPTIONS=(
    "Baseline touch-heavy"
    "Navigation focused"
    "High event count throttled"
    "Ignore crashes keep running"
    "System keys heavy"
    "Pinch zoom focus"
    "Fast stress test"
    "App switch heavy"
    "Slow realistic user simulation"
    "Full fault tolerance"
)

MONKEY_ARGS=(
    "-p $PACKAGE -s 1902834875253 --pct-touch 70 --pct-motion 10 -v 5000"
    "-p $PACKAGE -s 2845619073821 --pct-nav 50 --pct-majornav 25 -v 5000"
    "-p $PACKAGE -s 3719284056132 --throttle 200 -v 50000"
    "-p $PACKAGE -s 4521873946201 --ignore-crashes --ignore-timeouts -v 5000"
    "-p $PACKAGE -s 5634902817345 --pct-syskeys 40 --pct-touch 30 -v 5000"
    "-p $PACKAGE -s 6748291035467 --pct-pinchzoom 30 --pct-touch 40 -v 5000"
    "-p $PACKAGE -s 7856134920578 --pct-touch 50 --pct-motion 20 -v 50000"
    "-p $PACKAGE -s 8923047165689 --pct-appswitch 30 --pct-touch 40 -v 5000"
    "-p $PACKAGE -s 9034158276790 --throttle 500 --pct-touch 60 --pct-nav 20 -v 5000"
    "-p $PACKAGE -s 1234567890123 --ignore-crashes --ignore-timeouts --ignore-security-exceptions --monitor-native-crashes -v 5000"
)

TOTAL=${#DESCRIPTIONS[@]}
RUNS_EXECUTED=()

run_monkey() {
    local run_num=$1
    local idx=$((run_num - 1))
    local description="${DESCRIPTIONS[$idx]}"
    local args="${MONKEY_ARGS[$idx]}"
    local log_file="$LOG_DIR/monkey_run${run_num}.txt"
    local cmd="$ADB shell monkey $args"

    echo "[$run_num/$TOTAL] $description"
    echo "  Command: $cmd"

    echo "Command: $cmd" > "$log_file"
    echo "Description: $description" >> "$log_file"
    echo "Started: $(date)" >> "$log_file"
    echo "========================================" >> "$log_file"

    $ADB shell monkey $args 2>&1 | tee -a "$log_file"

    if grep -q "Monkey finished" "$log_file"; then
        echo "  PASSED - Log: $log_file"
    else
        echo "  FAILED - Log: $log_file"
    fi

    echo "Finished: $(date)" >> "$log_file"
    RUNS_EXECUTED+=("$run_num")
}

if [ "$RUN_FILTER" = "all" ]; then
    for i in $(seq 1 $TOTAL); do
        run_monkey "$i"
    done
else
    if [[ "$RUN_FILTER" -ge 1 && "$RUN_FILTER" -le $TOTAL ]]; then
        run_monkey "$RUN_FILTER"
    else
        echo "Error: --run must be between 1 and $TOTAL, or 'all'"
        exit 1
    fi
fi

echo ""
echo "========================================"
echo "Runs complete. Results in $LOG_DIR/"
echo ""
echo "Summary:"
for i in "${RUNS_EXECUTED[@]}"; do
    log="$LOG_DIR/monkey_run${i}.txt"
    cmd=$(head -1 "$log" | sed 's/^Command: //')
    if grep -q "Monkey finished" "$log"; then
        echo "  Run $i: PASSED  | $cmd"
    else
        echo "  Run $i: FAILED  | $cmd"
    fi
done
