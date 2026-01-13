#!/usr/bin/env bash
#
# xclip wrapper that reads from macOS clipboard bridge
# This intercepts clipboard paste operations in the container
#

BRIDGE_PATH="/shared/clipboard"
REAL_XCLIP="/usr/bin/xclip.real"
LOG="/tmp/xclip-debug.log"

# Log the call for debugging
echo "$(date): xclip called with args: $*" >> "$LOG"

# Check if this is a read operation
IS_READ=false
if [[ "$*" == *"-o"* ]] || [[ "$*" == *"--out"* ]] || [[ "$*" == *"-selection"* ]]; then
    IS_READ=true
fi

# If reading from clipboard
if [ "$IS_READ" = true ]; then
    echo "$(date): Reading clipboard" >> "$LOG"
    
    if [ -f "$BRIDGE_PATH.mime" ]; then
        MIME=$(cat "$BRIDGE_PATH.mime" 2>/dev/null || echo "")
        echo "$(date): MIME: $MIME" >> "$LOG"
        
        # Check if requesting image specifically
        if [[ "$*" == *"image/png"* ]] || [[ "$*" == *"-t image"* ]]; then
            echo "$(date): Image requested" >> "$LOG"
            
            # Check if we have an image
            if [[ "$MIME" == *"image"* ]] && [ -f "$BRIDGE_PATH.b64" ]; then
                # Decode base64 and output raw image data
                echo "$(date): Returning image (base64 decoded)" >> "$LOG"
                base64 -d "$BRIDGE_PATH.b64"
                exit 0
            else
                echo "$(date): No image available" >> "$LOG"
                # No image, exit with error
                exit 1
            fi
        fi
        
        # Text clipboard request
        if [[ "$MIME" == *"text"* ]] && [ -f "$BRIDGE_PATH.txt" ]; then
            echo "$(date): Returning text" >> "$LOG"
            cat "$BRIDGE_PATH.txt"
            exit 0
        fi
    else
        echo "$(date): No bridge file found" >> "$LOG"
    fi
fi

# Fall back to real xclip
echo "$(date): Falling back to real xclip" >> "$LOG"
if [ -x "$REAL_XCLIP" ]; then
    exec "$REAL_XCLIP" "$@"
else
    exit 1
fi
