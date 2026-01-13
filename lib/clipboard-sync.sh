#!/usr/bin/env bash
#
# Clipboard sync daemon for macOS → Docker container
# Continuously syncs macOS clipboard to a shared volume for OpenCode
# Supports multiple instances via PID file locking
#

set -euo pipefail

SHARED_DIR="${1:-}"

if [ -z "$SHARED_DIR" ]; then
    echo "Usage: $0 <shared-directory>" >&2
    exit 1
fi

mkdir -p "$SHARED_DIR"

PID_FILE="$SHARED_DIR/clipboard-sync.pid"

# Check if another daemon is already running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "[clipboard-sync] Daemon already running (PID: $OLD_PID)"
        exit 0
    else
        echo "[clipboard-sync] Stale PID file found, removing..."
        rm -f "$PID_FILE"
    fi
fi

# Write our PID
echo $$ > "$PID_FILE"

# Cleanup on exit
cleanup() {
    if [ -f "$PID_FILE" ] && [ "$(cat "$PID_FILE" 2>/dev/null)" = "$$" ]; then
        rm -f "$PID_FILE"
    fi
}
trap cleanup EXIT INT TERM

# Track last clipboard content to avoid unnecessary writes
LAST_TEXT=""
LAST_IMAGE_HASH=""

echo "[clipboard-sync] Starting clipboard sync to $SHARED_DIR (PID: $$)"
echo "[clipboard-sync] Polling every 300ms..."

# Create initial ready signal (even if clipboard is empty)
echo "text/plain" > "$SHARED_DIR/clipboard.mime"
touch "$SHARED_DIR/clipboard.txt"

while true; do
    # Try to detect if clipboard contains an image
    if osascript -e 'clipboard info' 2>/dev/null | grep -q 'picture'; then
        # Get image from clipboard
        TMPFILE=$(mktemp).png
        if osascript -e 'set imageData to the clipboard as "PNGf"' \
                      -e "set fileRef to open for access POSIX file \"$TMPFILE\" with write permission" \
                      -e 'set eof fileRef to 0' \
                      -e 'write imageData to fileRef' \
                      -e 'close access fileRef' 2>/dev/null; then
            
            # Check if image changed (avoid writing same image repeatedly)
            IMAGE_HASH=$(md5 -q "$TMPFILE" 2>/dev/null || echo "")
            if [ -n "$IMAGE_HASH" ] && [ "$IMAGE_HASH" != "$LAST_IMAGE_HASH" ]; then
                # Atomic write: write to temp, then move
                base64 -i "$TMPFILE" > "$SHARED_DIR/clipboard.b64.tmp"
                echo "image/png" > "$SHARED_DIR/clipboard.mime.tmp"
                mv "$SHARED_DIR/clipboard.b64.tmp" "$SHARED_DIR/clipboard.b64"
                mv "$SHARED_DIR/clipboard.mime.tmp" "$SHARED_DIR/clipboard.mime"
                
                LAST_IMAGE_HASH="$IMAGE_HASH"
                LAST_TEXT=""  # Clear text tracking
            fi
        fi
        rm -f "$TMPFILE"
    else
        # Get text from clipboard
        TEXT=$(pbpaste 2>/dev/null || echo "")
        
        # Only write if content changed
        if [ "$TEXT" != "$LAST_TEXT" ]; then
            # Atomic write: write to temp, then move
            echo -n "$TEXT" > "$SHARED_DIR/clipboard.txt.tmp"
            echo "text/plain" > "$SHARED_DIR/clipboard.mime.tmp"
            mv "$SHARED_DIR/clipboard.txt.tmp" "$SHARED_DIR/clipboard.txt"
            mv "$SHARED_DIR/clipboard.mime.tmp" "$SHARED_DIR/clipboard.mime"
            
            LAST_TEXT="$TEXT"
            LAST_IMAGE_HASH=""  # Clear image tracking
        fi
    fi
    
    sleep 0.3
done
