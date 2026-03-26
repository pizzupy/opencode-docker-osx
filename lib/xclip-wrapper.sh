#!/usr/bin/env bash
#
# xclip wrapper that bridges macOS clipboard to/from the container.
#
# Read (paste):  serves content from /shared (written by clipboard-sync.sh on host)
# Write (copy):  writes content to /shared-out (picked up by clipboard-sync.sh on host)
#

BRIDGE_PATH="/shared/clipboard"
BRIDGE_OUT_DIR="/shared-out"
REAL_XCLIP="/usr/bin/xclip.real"

# Determine operation direction
IS_READ=false
for arg in "$@"; do
    if [[ "$arg" == "-o" || "$arg" == "--out" ]]; then
        IS_READ=true
        break
    fi
done

# --- READ (paste) ---
if [ "$IS_READ" = true ]; then
    if [ -f "$BRIDGE_PATH.mime" ]; then
        MIME=$(cat "$BRIDGE_PATH.mime" 2>/dev/null || echo "")

        # Image requested specifically
        if [[ "$*" == *"image/png"* ]] || [[ "$*" == *"-t image"* ]]; then
            if [[ "$MIME" == *"image"* ]] && [ -f "$BRIDGE_PATH.b64" ]; then
                base64 -d "$BRIDGE_PATH.b64"
                exit 0
            else
                exit 1
            fi
        fi

        # Text
        if [[ "$MIME" == *"text"* ]] && [ -f "$BRIDGE_PATH.txt" ]; then
            cat "$BRIDGE_PATH.txt"
            exit 0
        fi
    fi

    # Fall back to real xclip
    [ -x "$REAL_XCLIP" ] && exec "$REAL_XCLIP" "$@"
    exit 1
fi

# --- WRITE (copy) ---
if [ -d "$BRIDGE_OUT_DIR" ]; then
    # Check if writing an image
    if [[ "$*" == *"image/png"* ]] || [[ "$*" == *"-t image"* ]]; then
        base64 > "$BRIDGE_OUT_DIR/clipboard-out.b64"
        echo "image/png" > "$BRIDGE_OUT_DIR/clipboard-out.mime"
        exit 0
    fi

    # Default: write text
    CONTENT=$(cat)
    printf '%s' "$CONTENT" > "$BRIDGE_OUT_DIR/clipboard-out.txt"
    echo "text/plain" > "$BRIDGE_OUT_DIR/clipboard-out.mime"
    exit 0
fi

# Fall back to real xclip for write
[ -x "$REAL_XCLIP" ] && exec "$REAL_XCLIP" "$@"
exit 0
