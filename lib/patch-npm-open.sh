#!/bin/bash
# Patch ALL xdg-open binaries in npm cache to use our bridge
# This runs at container startup and monitors for new npx-installed packages
# Catches: open package, playwright, and any other bundled xdg-open binaries

set -e

# Create the bridge wrapper for xdg-open (used by Node's bundled open packages)
cat > /usr/local/bin/xdg-open-bridge << 'EOF'
#!/bin/bash
# Bridge wrapper for Node's open package — delegates to container-open-wrapper

URL="$1"

if [ -f "${URL_BRIDGE_CONFIG:-/tmp/url-bridge/bridge.conf}" ]; then
    exec /usr/local/bin/container-open-wrapper "$URL"
fi

# Bridge not available — exit successfully so callers don't fail
exit 0
EOF

chmod +x /usr/local/bin/xdg-open-bridge

# Function to patch open packages
patch_open_packages() {
    # Find ALL xdg-open binaries in npm cache (not just the 'open' package)
    # This catches bundled xdg-open in playwright, open, and any other packages
    find /root/.npm -name "xdg-open" -type f 2>/dev/null | while read xdg_open; do
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
