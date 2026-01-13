#!/usr/bin/env bash
#
# OpenCode entrypoint that starts Xvfb for clipboard support
#

# Start Xvfb on display :99 in the background
Xvfb :99 -screen 0 1024x768x24 > /dev/null 2>&1 &
XVFB_PID=$!

# Wait a moment for Xvfb to start
sleep 0.5

# Cleanup function
cleanup() {
    if [ -n "$XVFB_PID" ]; then
        kill $XVFB_PID 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

# Run opencode with all arguments
exec opencode "$@"
