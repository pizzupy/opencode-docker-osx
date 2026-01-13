#!/usr/bin/env bash
#
# start-mcp-proxy.sh - Start mcp-proxy for Linear OAuth on Mac host
#
# This runs mcp-proxy on the Mac host so OAuth callbacks work.
# Docker containers connect via host.docker.internal:8080
#

set -euo pipefail

PROXY_PORT="${PROXY_PORT:-8080}"
PROXY_HOST="${PROXY_HOST:-0.0.0.0}"
PROXY_CONFIG="${PROXY_CONFIG:-$HOME/.cache/mcp-proxy-config.json}"
LINEAR_URL="${LINEAR_URL:-https://mcp.linear.app/mcp}"

# Check if already running
if lsof -Pi :$PROXY_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "✓ mcp-proxy already running on port $PROXY_PORT"
    exit 0
fi

echo "Starting mcp-proxy for Linear OAuth..."
echo "  Port: $PROXY_PORT"
echo "  Host: $PROXY_HOST"
echo "  Target: $LINEAR_URL"
echo ""
echo "OAuth callbacks will be handled on this Mac."
echo "Docker containers should connect to: http://host.docker.internal:$PROXY_PORT/sse"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Start mcp-proxy in server mode
# This proxies to remote OAuth MCP servers and exposes them as SSE endpoints
#
# If a config file exists, use it (supports multiple services)
# Otherwise, fall back to Linear-only mode (backward compatibility)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$PROXY_CONFIG" ]; then
    echo "Using config file: $PROXY_CONFIG"
    echo ""
    
    # Use the generator script to create the command with multiple --named-server arguments
    # This is more reliable than --named-server-config which has issues with shell parsing
    exec "$SCRIPT_DIR/generate-mcp-proxy-start.sh"
else
    echo "No config file found at: $PROXY_CONFIG"
    echo "Using Linear-only mode (backward compatibility)"
    echo ""
    
    # Fall back to Linear-only mode
    # --named-server: Creates a named server at /servers/linear/sse
    # --port: Listen on this port for incoming connections
    # --host: Bind to 0.0.0.0 so Docker can reach it
    # --allow-origin: Allow CORS from anywhere (needed for OAuth redirects)
    exec mcp-proxy \
        --named-server linear "npx -y mcp-remote $LINEAR_URL" \
        --port "$PROXY_PORT" \
        --host "$PROXY_HOST" \
        --allow-origin '*'
fi
