#!/usr/bin/env bash
#
# OpenCode entrypoint that preserves TTY for proper clipboard support
# This script starts background services then EXEC's OpenCode to preserve TTY
#

set -euo pipefail

# Start Xvfb for clipboard support (in case xsel/xclip are used)
echo "[Container] Starting Xvfb for clipboard..."
Xvfb :99 -screen 0 1024x768x24 > /dev/null 2>&1 &
XVFB_PID=$!
sleep 0.5
echo "[Container] Xvfb started (PID: $XVFB_PID)"

# Start the npm package patcher in watch mode
echo "[Container] Starting npm package patcher..."
PATCH_NPM_OPEN_WATCH=1 /usr/local/bin/patch-npm-open > /dev/null 2>&1 &
PATCHER_PID=$!
echo "[Container] Patcher started (PID: $PATCHER_PID)"

# Cleanup function for background processes
cleanup() {
    echo "[Container] Cleaning up background processes..."
    kill $PATCHER_PID 2>/dev/null || true
    kill $XVFB_PID 2>/dev/null || true
}

# Register cleanup on exit
trap cleanup EXIT INT TERM

# Enable bracketed paste mode explicitly
# This tells the terminal to wrap pasted content in escape sequences
printf '\e[?2004h'

echo "[Container] Launching OpenCode with TTY passthrough..."
echo "[Container] Terminal: $TERM, Display: $DISPLAY"

# EXEC replaces this script with OpenCode, preserving the TTY connection
# This is crucial for proper terminal control sequence handling (OSC52, bracketed paste, etc.)
exec opencode "$@"
