#!/usr/bin/env bash
#
# xsel wrapper that bridges macOS clipboard to/from the container.
#
# Read (paste):  serves content from /shared (written by clipboard-sync.sh on host)
# Write (copy):  writes content to /shared-out (picked up by clipboard-sync.sh on host)
#

BRIDGE_PATH="/shared/clipboard"
BRIDGE_OUT_DIR="/shared-out"
REAL_XSEL="/usr/bin/xsel.real"

# Determine operation direction
IS_READ=false
IS_WRITE=false
for arg in "$@"; do
    if [[ "$arg" == "-o" || "$arg" == "--output" ]]; then
        IS_READ=true
    fi
    if [[ "$arg" == "-i" || "$arg" == "--input" ]]; then
        IS_WRITE=true
    fi
done
# xsel with no args defaults to output (read)
if [ $# -eq 0 ]; then
    IS_READ=true
fi

# --- READ (paste) ---
if [ "$IS_READ" = true ]; then
    if [ -f "$BRIDGE_PATH.mime" ]; then
        MIME=$(cat "$BRIDGE_PATH.mime" 2>/dev/null || echo "")

        if [[ "$MIME" == *"text"* ]] && [ -f "$BRIDGE_PATH.txt" ]; then
            cat "$BRIDGE_PATH.txt"
            exit 0
        fi

        if [[ "$MIME" == *"image"* ]] && [ -f "$BRIDGE_PATH.b64" ]; then
            base64 -d "$BRIDGE_PATH.b64"
            exit 0
        fi
    fi

    [ -x "$REAL_XSEL" ] && exec "$REAL_XSEL" "$@"
    exit 0
fi

# --- WRITE (copy) ---
if [ "$IS_WRITE" = true ] && [ -d "$BRIDGE_OUT_DIR" ]; then
    CONTENT=$(cat)
    printf '%s' "$CONTENT" > "$BRIDGE_OUT_DIR/clipboard-out.txt"
    echo "text/plain" > "$BRIDGE_OUT_DIR/clipboard-out.mime"
    exit 0
fi

# Fall back to real xsel
[ -x "$REAL_XSEL" ] && exec "$REAL_XSEL" "$@"
exit 0
