#!/bin/bash
#
# Container Open Wrapper
#
# Replaces 'open' and 'xdg-open' commands in the container to bridge to host.
# Reads port and token from shared config and makes HTTP request to host service.
#
# Handles:
#   - URLs (http/https)  → passed through as-is
#   - Bare file paths    → translated to host paths and wrapped as file:// URLs
#   - /root/...          → translated to $HOST_HOME/... on the host

set -euo pipefail

CONFIG_FILE="${URL_BRIDGE_CONFIG:-/tmp/url-bridge/bridge.conf}"
TIMEOUT=5

# Read config
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: URL bridge config not found: $CONFIG_FILE" >&2
    echo "The host-url-opener service may not be running." >&2
    exit 1
fi

# Source the config to get PORT and TOKEN
source "$CONFIG_FILE"

if [ -z "${PORT:-}" ] || [ -z "${TOKEN:-}" ]; then
    echo "Error: Invalid bridge config (missing PORT or TOKEN)" >&2
    exit 1
fi

# Get URL/path from arguments (skip flags)
TARGET=""
for arg in "$@"; do
    if [[ "$arg" != -* ]]; then
        TARGET="$arg"
        break
    fi
done

if [ -z "$TARGET" ]; then
    echo "Error: No URL or path provided" >&2
    echo "Usage: $(basename "$0") <url-or-path>" >&2
    exit 1
fi

# Determine if this is a bare file path (not a URL with a scheme)
if [[ "$TARGET" != *"://"* ]]; then
    # Bare path — translate container path to host path
    HOST_HOME="${HOST_HOME:-/root}"

    # Resolve ~ to /root (container home)
    if [[ "$TARGET" == "~/"* ]]; then
        TARGET="/root/${TARGET:2}"
    elif [[ "$TARGET" == "~" ]]; then
        TARGET="/root"
    fi

    # Translate /root/... to $HOST_HOME/... for the host
    if [[ "$TARGET" == /root/* ]]; then
        TARGET="${HOST_HOME}${TARGET#/root}"
    elif [[ "$TARGET" == "/root" ]]; then
        TARGET="$HOST_HOME"
    fi

    # Wrap as file:// URL
    TARGET="file://${TARGET}"
fi

# Make request to host service
HOST="host.docker.internal"
ENDPOINT="http://${HOST}:${PORT}/open"

response=$(curl -s -w "\n%{http_code}" \
    --max-time "$TIMEOUT" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${TOKEN}" \
    -d "{\"url\":\"$TARGET\"}" \
    "$ENDPOINT" 2>&1) || {
    echo "Error: Failed to connect to URL bridge service" >&2
    echo "Make sure the host service is running and accessible" >&2
    exit 1
}

# Parse response (last line is status code)
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$http_code" = "200" ]; then
    exit 0
else
    echo "Error: Failed to open (HTTP $http_code)" >&2
    echo "$body" >&2
    exit 1
fi
