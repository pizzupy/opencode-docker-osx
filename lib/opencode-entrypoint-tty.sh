#!/usr/bin/env bash
#
# OpenCode entrypoint that preserves TTY for proper clipboard support
# This script starts background services then EXEC's OpenCode to preserve TTY
#

set -euo pipefail

# Generate a unique ID for this container instance
# This prevents conflicts when multiple containers share /tmp
CONTAINER_ID="${CONTAINER_ID:-$$}"  # Use PID if CONTAINER_ID not set
DISPLAY_NUM=$((99 + ($CONTAINER_ID % 100)))  # Display :99-:198

# Create container-specific log directory if /tmp is shared
LOG_DIR="/tmp/opencode-${CONTAINER_ID}"
mkdir -p "$LOG_DIR"

echo "[Container] Instance ID: $CONTAINER_ID (Display :$DISPLAY_NUM)"

# Start Xvfb for clipboard support (in case xsel/xclip are used)
# Use unique display number to avoid conflicts when containers share /tmp
echo "[Container] Starting Xvfb on display :$DISPLAY_NUM..."
Xvfb ":$DISPLAY_NUM" -screen 0 1024x768x24 > /dev/null 2>&1 &
XVFB_PID=$!
sleep 0.5

# Update DISPLAY to match our Xvfb
export DISPLAY=":$DISPLAY_NUM"
echo "[Container] Xvfb started (PID: $XVFB_PID, DISPLAY: $DISPLAY)"

# Start the npm package patcher in watch mode
# Use unique log file to avoid conflicts when containers share /tmp
echo "[Container] Starting npm package patcher..."
PATCH_NPM_OPEN_WATCH=1 /usr/local/bin/patch-npm-open > "$LOG_DIR/patch-npm-open.log" 2>&1 &
PATCHER_PID=$!
echo "[Container] Patcher started (PID: $PATCHER_PID)"

# Verify patcher is still running after a moment
sleep 0.5
if ! kill -0 $PATCHER_PID 2>/dev/null; then
    echo "[Container] WARNING: Patcher process died immediately!"
    echo "[Container] Check $LOG_DIR/patch-npm-open.log for errors"
fi

# Start process monitor in background (optional, for debugging)
if [ "${ENABLE_PROCESS_MONITOR:-false}" = "true" ]; then
    echo "[Container] Starting process monitor..."
    LOG_FILE="$LOG_DIR/process-monitor.log" /usr/local/bin/monitor-processes.sh &
    MONITOR_PID=$!
    echo "[Container] Process monitor started (PID: $MONITOR_PID)"
    echo "[Container] Monitor log: $LOG_DIR/process-monitor.log"
fi

# Cleanup function for background processes
cleanup() {
    echo "[Container] Cleaning up background processes..."
    
    # Kill the entire process group to catch backgrounded children
    kill -- -$PATCHER_PID 2>/dev/null || true
    kill $PATCHER_PID 2>/dev/null || true
    kill $XVFB_PID 2>/dev/null || true
    [ -n "${MONITOR_PID:-}" ] && kill $MONITOR_PID 2>/dev/null || true
    
    # Clean up container-specific log directory
    if [ -n "${LOG_DIR:-}" ] && [ -d "$LOG_DIR" ]; then
        echo "[Container] Cleaning up log directory: $LOG_DIR"
        rm -rf "$LOG_DIR"
    fi
}

# Cleanup terminal state on exit
cleanup_terminal() {
    local exit_code=$?
    
    # Clean up background processes first
    cleanup
    
    # Reset terminal state
    echo "[Container] Resetting terminal state..."
    # Disable bracketed paste mode
    printf '\e[?2004l' 2>/dev/null || true
    # Show cursor (in case it was hidden)
    printf '\e[?25h' 2>/dev/null || true
    # Reset colors and attributes
    printf '\e[0m' 2>/dev/null || true
    # Reset terminal to sane state (non-blocking)
    stty sane 2>/dev/null || true
    
    echo "[Container] OpenCode exited with code $exit_code"
    
    # Pause to let user read cleanup messages
    # Set to 'never' to disable, or number of seconds for timeout
    PAUSE_ON_EXIT="${PAUSE_ON_EXIT:-5}"
    if [ "$PAUSE_ON_EXIT" != "never" ]; then
        echo "[Container] Press Enter to close container (or wait ${PAUSE_ON_EXIT}s)..."
        read -t "$PAUSE_ON_EXIT" || true
    fi
    
    exit $exit_code
}

# Register cleanup on exit
trap cleanup_terminal EXIT INT TERM

# Enable bracketed paste mode explicitly
# This tells the terminal to wrap pasted content in escape sequences
printf '\e[?2004h'

echo "[Container] Launching OpenCode..."
echo "[Container] Terminal: $TERM, Display: $DISPLAY"

# Run opencode directly (not exec) so cleanup trap can run when it exits
# 
# Trade-off explanation:
# - Using 'exec opencode' would replace this shell with opencode, preserving PID 1
#   and providing perfect signal passthrough, but cleanup trap would never run
# - Using 'opencode' keeps this shell alive, allowing cleanup trap to run and
#   reset terminal state, but adds one extra process in the chain
# 
# We chose cleanup capability over perfect signal passthrough because:
# 1. Terminal state MUST be reset or user's shell becomes unusable
# 2. Signal handling still works (this shell forwards signals to opencode)
# 3. The extra process has negligible overhead
# 
# If signal handling issues arise, consider using a C wrapper or handling
# terminal reset in the Docker host script instead.
opencode "$@"

# Capture exit code
OPENCODE_EXIT=$?

# Exit with opencode's exit code (cleanup trap will run)
exit $OPENCODE_EXIT
