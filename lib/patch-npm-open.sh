#!/bin/bash
# Patch Node's 'open' package to use our bridge
# This runs at container startup to patch any npx-installed packages

set -e

# Create the bridge wrapper for xdg-open with enhanced logging
cat > /usr/local/bin/xdg-open-bridge << 'EOF'
#!/bin/bash
# Bridge wrapper for Node's open package - WITH ENHANCED LOGGING

# UNCONDITIONAL LOGGING - Log that we were called, no matter what
LOG_FILE="/tmp/xdg-open-bridge-calls.log"
echo "=== XDG-OPEN-BRIDGE CALLED ===" >> "$LOG_FILE" 2>&1 || true
echo "Time: $(date)" >> "$LOG_FILE" 2>&1 || true
echo "Args: $*" >> "$LOG_FILE" 2>&1 || true
echo "PWD: $PWD" >> "$LOG_FILE" 2>&1 || true
echo "PID: $$, PPID: $PPID" >> "$LOG_FILE" 2>&1 || true

URL="$1"
echo "URL to open: $URL" >> "$LOG_FILE" 2>&1 || true

# If bridge is available, use it
if [ -f "${URL_BRIDGE_CONFIG:-/tmp/url-bridge/bridge.conf}" ]; then
    echo "Bridge config found" >> "$LOG_FILE" 2>&1 || true
    source "${URL_BRIDGE_CONFIG}"
    
    # Debug: Uncomment to log port and partial token
    # echo "PORT=$PORT, TOKEN=${TOKEN:0:10}..." >> "$LOG_FILE" 2>&1 || true
    
    # Call the bridge
    response=$(curl -s -w "\n%{http_code}" --max-time 5 \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${TOKEN}" \
        -d "{\"url\":\"$URL\"}" \
        "http://host.docker.internal:${PORT}/open" 2>&1) || {
        echo "ERROR: curl failed: $response" >> "$LOG_FILE" 2>&1 || true
        exit 0
    }
    
    http_code=$(echo "$response" | tail -n 1)
    echo "Bridge response: HTTP $http_code" >> "$LOG_FILE" 2>&1 || true
    echo "==================" >> "$LOG_FILE" 2>&1 || true
    
    exit 0
else
    echo "Bridge config NOT found at ${URL_BRIDGE_CONFIG:-/tmp/url-bridge/bridge.conf}" >> "$LOG_FILE" 2>&1 || true
    echo "==================" >> "$LOG_FILE" 2>&1 || true
    # Bridge not available, just exit successfully
    # so mcp-remote doesn't fail
    exit 0
fi
EOF

chmod +x /usr/local/bin/xdg-open-bridge

# Function to patch open packages
patch_open_packages() {
    # Find all open package installations in npm cache
    find /root/.npm -name "xdg-open" -path "*/node_modules/open/xdg-open" 2>/dev/null | while read xdg_open; do
        if [ -f "$xdg_open" ] && [ ! -f "${xdg_open}.original" ]; then
            mv "$xdg_open" "${xdg_open}.original"
            cp /usr/local/bin/xdg-open-bridge "$xdg_open"
            chmod +x "$xdg_open"
        fi
    done
}

# Patch existing packages
patch_open_packages

# Monitor for new npx installations and patch them
# This runs in the background
if [ "${PATCH_NPM_OPEN_WATCH:-}" = "1" ]; then
    # Don't background - let this script become the monitoring loop
    # This prevents zombie processes
    while true; do
        sleep 2
        patch_open_packages
    done
fi
