#!/usr/bin/env bash
#
# xsel wrapper that reads from macOS clipboard bridge
# This intercepts clipboard paste operations in the container
#

BRIDGE_PATH="/shared/clipboard"
REAL_XSEL="/usr/bin/xsel.real"

# If reading from clipboard (paste operation)
if [[ "$*" == *"-o"* ]] || [[ "$*" == *"--output"* ]] || [ $# -eq 0 ]; then
    # Check if bridge is available
    if [ -f "$BRIDGE_PATH.mime" ]; then
        MIME=$(cat "$BRIDGE_PATH.mime" 2>/dev/null || echo "")
        
        # For text clipboard
        if [[ "$MIME" == *"text"* ]] && [ -f "$BRIDGE_PATH.txt" ]; then
            cat "$BRIDGE_PATH.txt"
            exit 0
        fi
        
        # For images, output base64
        if [[ "$MIME" == *"image"* ]] && [ -f "$BRIDGE_PATH.b64" ]; then
            cat "$BRIDGE_PATH.b64"
            exit 0
        fi
    fi
fi

# Fall back to real xsel for all other operations (or if bridge not available)
if [ -x "$REAL_XSEL" ]; then
    exec "$REAL_XSEL" "$@"
else
    # If real xsel doesn't exist, just return empty
    exit 0
fi
