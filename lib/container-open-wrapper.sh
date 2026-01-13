#!/bin/bash
#
# Container Open Wrapper
#
# Replaces 'open' and 'xdg-open' commands in the container to bridge to host.
# Reads port and token from shared config and makes HTTP request to host service.

# UNCONDITIONAL LOGGING - Log that we were called, no matter what
LOG_FILE="/tmp/wrapper-execution.log"
echo "=== WRAPPER CALLED ===" >> "$LOG_FILE" 2>&1 || true
echo "Time: $(date)" >> "$LOG_FILE" 2>&1 || true
echo "Command: $0" >> "$LOG_FILE" 2>&1 || true
echo "Args: $*" >> "$LOG_FILE" 2>&1 || true
echo "PWD: $PWD" >> "$LOG_FILE" 2>&1 || true
echo "PID: $$" >> "$LOG_FILE" 2>&1 || true
echo "PPID: $PPID" >> "$LOG_FILE" 2>&1 || true
env >> "$LOG_FILE" 2>&1 || true
echo "==================" >> "$LOG_FILE" 2>&1 || true

set -euo pipefail

CONFIG_FILE="${URL_BRIDGE_CONFIG:-/tmp/url-bridge/bridge.conf}"
TIMEOUT=5

# Read config
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: URL bridge config not found: $CONFIG_FILE" >&2
    echo "The host-url-opener service may not be running." >&2
    echo "ERROR: Config not found at $CONFIG_FILE" >> "$LOG_FILE" 2>&1 || true
    exit 1
fi

# Source the config to get PORT and TOKEN
source "$CONFIG_FILE"

if [ -z "${PORT:-}" ] || [ -z "${TOKEN:-}" ]; then
    echo "Error: Invalid bridge config (missing PORT or TOKEN)" >&2
    echo "ERROR: Invalid config" >> "$LOG_FILE" 2>&1 || true
    exit 1
fi

echo "Bridge config loaded: PORT=$PORT" >> "$LOG_FILE" 2>&1 || true

# Get URL from arguments
URL=""
for arg in "$@"; do
    # Skip flags/options
    if [[ "$arg" != -* ]]; then
        URL="$arg"
        break
    fi
done

if [ -z "$URL" ]; then
    echo "Error: No URL provided" >&2
    echo "Usage: $(basename "$0") <url>" >&2
    echo "ERROR: No URL provided" >> "$LOG_FILE" 2>&1 || true
    exit 1
fi

echo "Opening URL: $URL" >> "$LOG_FILE" 2>&1 || true

# Make request to host service
# Use host.docker.internal to reach macOS host from container
HOST="host.docker.internal"
ENDPOINT="http://${HOST}:${PORT}/open"

response=$(curl -s -w "\n%{http_code}" \
    --max-time "$TIMEOUT" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${TOKEN}" \
    -d "{\"url\":\"$URL\"}" \
    "$ENDPOINT" 2>&1) || {
    echo "Error: Failed to connect to URL bridge service" >&2
    echo "Make sure the host service is running and accessible" >&2
    echo "ERROR: curl failed" >> "$LOG_FILE" 2>&1 || true
    exit 1
}

# Parse response (last line is status code)
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" = "200" ]; then
    # Success - optionally show message
    # echo "URL opened: $URL" >&2
    echo "SUCCESS: HTTP 200" >> "$LOG_FILE" 2>&1 || true
    exit 0
else
    echo "Error: Failed to open URL (HTTP $http_code)" >&2
    echo "$body" >&2
    echo "ERROR: HTTP $http_code - $body" >> "$LOG_FILE" 2>&1 || true
    exit 1
fi
