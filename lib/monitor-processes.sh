#!/usr/bin/env bash
#
# Monitor background processes and log when they die
# This helps debug unexpected container exits
#

set -euo pipefail

# Use LOG_FILE env var if set, otherwise default to /tmp
LOG_FILE="${LOG_FILE:-/tmp/process-monitor.log}"

echo "[$(date)] Process monitor started" >> "$LOG_FILE"

# Monitor key processes
while true; do
    # Check Xvfb (any display number)
    if ! pgrep -f "Xvfb" > /dev/null; then
        echo "[$(date)] WARNING: Xvfb is not running!" >> "$LOG_FILE"
    fi
    
    # Check patch-npm-open
    if ! pgrep -f "patch-npm-open" > /dev/null; then
        echo "[$(date)] WARNING: patch-npm-open is not running!" >> "$LOG_FILE"
    fi
    
    # Check opencode
    if ! pgrep -f "opencode" > /dev/null; then
        echo "[$(date)] CRITICAL: opencode is not running!" >> "$LOG_FILE"
        break
    fi
    
    # Log process count every 5 minutes
    if [ $((SECONDS % 300)) -eq 0 ]; then
        echo "[$(date)] Process count: $(ps aux | wc -l)" >> "$LOG_FILE"
        echo "[$(date)] Memory: $(free -h | grep Mem:)" >> "$LOG_FILE"
    fi
    
    sleep 10
done

echo "[$(date)] Process monitor exiting" >> "$LOG_FILE"
