#!/usr/bin/env bash
#
# Manage the shared clipboard bridge daemon
# Usage: manage-clipboard-bridge.sh {start|stop|status|restart}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIPBOARD_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/opencode/clipboard-bridge"
PID_FILE="$CLIPBOARD_DIR/clipboard-sync.pid"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

get_pid() {
    if [ -f "$PID_FILE" ]; then
        cat "$PID_FILE" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

is_running() {
    local pid=$(get_pid)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

cmd_start() {
    if is_running; then
        echo -e "${GREEN}Clipboard bridge is already running (PID: $(get_pid))${NC}"
        return 0
    fi
    
    mkdir -p "$CLIPBOARD_DIR"
    echo "Starting clipboard bridge..."
    "$SCRIPT_DIR/clipboard-sync.sh" "$CLIPBOARD_DIR" > /dev/null 2>&1 &
    
    # Wait for it to start
    for i in {1..10}; do
        if is_running; then
            echo -e "${GREEN}✓ Clipboard bridge started (PID: $(get_pid))${NC}"
            return 0
        fi
        sleep 0.3
    done
    
    echo -e "${RED}✗ Failed to start clipboard bridge${NC}"
    return 1
}

cmd_stop() {
    if ! is_running; then
        echo -e "${YELLOW}Clipboard bridge is not running${NC}"
        # Clean up stale PID file
        rm -f "$PID_FILE"
        return 0
    fi
    
    local pid=$(get_pid)
    echo "Stopping clipboard bridge (PID: $pid)..."
    kill "$pid" 2>/dev/null || true
    
    # Wait for it to stop
    for i in {1..10}; do
        if ! is_running; then
            echo -e "${GREEN}✓ Clipboard bridge stopped${NC}"
            return 0
        fi
        sleep 0.3
    done
    
    # Force kill if still running
    if is_running; then
        echo "Force killing..."
        kill -9 "$pid" 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
    
    echo -e "${GREEN}✓ Clipboard bridge stopped${NC}"
}

cmd_status() {
    if is_running; then
        echo -e "${GREEN}Clipboard bridge is running (PID: $(get_pid))${NC}"
        echo "Directory: $CLIPBOARD_DIR"
        if [ -f "$CLIPBOARD_DIR/clipboard.mime" ]; then
            local mime=$(cat "$CLIPBOARD_DIR/clipboard.mime" 2>/dev/null || echo "unknown")
            echo "Last clipboard type: $mime"
        fi
        return 0
    else
        echo -e "${YELLOW}Clipboard bridge is not running${NC}"
        if [ -f "$PID_FILE" ]; then
            echo -e "${YELLOW}(Stale PID file exists)${NC}"
        fi
        return 1
    fi
}

cmd_restart() {
    cmd_stop
    sleep 0.5
    cmd_start
}

# Main
COMMAND="${1:-status}"

case "$COMMAND" in
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    status)
        cmd_status
        ;;
    restart)
        cmd_restart
        ;;
    *)
        echo "Usage: $0 {start|stop|status|restart}"
        exit 1
        ;;
esac
