#!/usr/bin/env bash
#
# start-mcp-proxy.sh - Start mcp-proxy on Mac host
#
# Runs mcp-proxy on the Mac host so OAuth callbacks work and host-only MCPs
# (e.g. playwright) can be served to the Docker container.
# Docker containers connect via host.docker.internal:8080
#

set -euo pipefail

PROXY_PORT="${PROXY_PORT:-8080}"
PROXY_HOST="${PROXY_HOST:-0.0.0.0}"
PROXY_CONFIG="${PROXY_CONFIG:-$HOME/.cache/mcp-proxy-config.json}"

# Check if already running
if lsof -Pi :$PROXY_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "✓ mcp-proxy already running on port $PROXY_PORT"
    exit 0
fi

echo "Starting mcp-proxy..."
echo "  Port: $PROXY_PORT"
echo "  Host: $PROXY_HOST"
echo ""
echo "Docker containers should connect to: http://host.docker.internal:$PROXY_PORT/sse"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Start mcp-proxy in server mode
# This proxies to remote OAuth MCP servers and exposes them as SSE endpoints
# Uses --named-server-config to pass the JSON config file directly,
# avoiding shell quoting issues with --named-server CLI args.

if [ ! -f "$PROXY_CONFIG" ]; then
    echo "No config file found at: $PROXY_CONFIG"
    echo "Run detect-remote-mcps.py to generate it."
    exit 1
fi

echo "Using config file: $PROXY_CONFIG"
echo ""

exec mcp-proxy \
    --named-server-config "$PROXY_CONFIG" \
    --port "$PROXY_PORT" \
    --host "$PROXY_HOST" \
    --pass-environment \
    --allow-origin '*'
