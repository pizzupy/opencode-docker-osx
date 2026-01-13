#!/usr/bin/env bash
#
# manage-mcp-proxy.sh - Manage mcp-proxy background service
#
# Usage:
#   ./manage-mcp-proxy.sh start   - Start mcp-proxy in background
#   ./manage-mcp-proxy.sh stop    - Stop mcp-proxy
#   ./manage-mcp-proxy.sh status  - Check if running
#   ./manage-mcp-proxy.sh restart - Restart mcp-proxy
#   ./manage-mcp-proxy.sh logs    - Show logs
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$HOME/.cache/mcp-proxy.pid"
LOG_FILE="$HOME/.cache/mcp-proxy.log"
PROXY_PORT="${PROXY_PORT:-8080}"

# Ensure cache directory exists
mkdir -p "$HOME/.cache"

is_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            # Stale PID file
            rm -f "$PID_FILE"
            return 1
        fi
    fi
    return 1
}

start_proxy() {
    if is_running; then
        echo "✓ mcp-proxy is already running (PID $(cat "$PID_FILE"))"
        return 0
    fi
    
    # Check if port is already in use by another process
    if lsof -Pi :$PROXY_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        # Port is in use - try to find the actual mcp-proxy PID
        local port_pid=$(lsof -Pi :$PROXY_PORT -sTCP:LISTEN -t 2>/dev/null | head -1)
        if [ -n "$port_pid" ]; then
            # Verify it's actually mcp-proxy
            if ps -p "$port_pid" -o command= | grep -q "mcp-proxy"; then
                echo "✓ mcp-proxy already running on port $PROXY_PORT (PID $port_pid)"
                echo "$port_pid" > "$PID_FILE"
                echo "  Logs: $LOG_FILE"
                echo "  Connect from Docker: http://host.docker.internal:$PROXY_PORT/sse"
                return 0
            else
                echo "✗ Port $PROXY_PORT is in use by another process (PID $port_pid)"
                echo "  Stop that process first or use a different port"
                return 1
            fi
        fi
    fi
    
    echo "Starting mcp-proxy in background..."
    
    # Start in background and save PID
    nohup "$SCRIPT_DIR/lib/start-mcp-proxy.sh" > "$LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"
    
    # Wait a moment and verify it started
    sleep 2
    if is_running; then
        echo "✓ mcp-proxy started successfully (PID $pid)"
        echo "  Logs: $LOG_FILE"
        echo "  Connect from Docker: http://host.docker.internal:$PROXY_PORT/sse"
        return 0
    else
        echo "✗ Failed to start mcp-proxy"
        echo "  Check logs: $LOG_FILE"
        return 1
    fi
}

stop_proxy() {
    if ! is_running; then
        echo "mcp-proxy is not running"
        return 0
    fi
    
    local pid=$(cat "$PID_FILE")
    echo "Stopping mcp-proxy (PID $pid)..."
    
    kill "$pid" 2>/dev/null || true
    
    # Wait for it to stop
    for i in {1..10}; do
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$PID_FILE"
            echo "✓ mcp-proxy stopped"
            return 0
        fi
        sleep 0.5
    done
    
    # Force kill if still running
    echo "Force stopping..."
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$PID_FILE"
    echo "✓ mcp-proxy stopped (forced)"
}

status_proxy() {
    if is_running; then
        local pid=$(cat "$PID_FILE")
        echo "✓ mcp-proxy is running (PID $pid)"
        
        # Detect actual port from process command line
        local actual_port=$(ps -p "$pid" -o args= 2>/dev/null | grep -o '\--port [0-9]*' | awk '{print $2}')
        if [ -n "$actual_port" ]; then
            echo "  Port: $actual_port"
            # Check if port is actually listening
            if lsof -Pi :$actual_port -sTCP:LISTEN -t >/dev/null 2>&1; then
                echo "  Status: Listening on port $actual_port"
            else
                echo "  Warning: Process running but not listening on port $actual_port"
            fi
        else
            echo "  Port: $PROXY_PORT (default)"
            echo "  Warning: Could not detect actual port from process"
        fi
        
        echo "  Logs: $LOG_FILE"
        return 0
    else
        echo "✗ mcp-proxy is not running"
        return 1
    fi
}

show_logs() {
    if [ -f "$LOG_FILE" ]; then
        echo "=== mcp-proxy logs ==="
        tail -50 "$LOG_FILE"
    else
        echo "No logs found at $LOG_FILE"
    fi
}

case "${1:-}" in
    start)
        start_proxy
        ;;
    stop)
        stop_proxy
        ;;
    restart)
        stop_proxy
        start_proxy
        ;;
    status)
        status_proxy
        ;;
    logs)
        show_logs
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs}"
        exit 1
        ;;
esac
