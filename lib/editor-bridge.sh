#!/bin/bash
#
# Editor Bridge
#
# Used as $EDITOR inside the container. Copies the file to a host-accessible
# location (opencode state dir, which is mounted), then opens it on the host
# via the URL bridge.
#
# opencode's /export writes a temp .md file, calls $EDITOR with it, waits for
# exit, then reads back the content. We open the file on the host and exit
# immediately — the content is unchanged, which is fine for viewing/exporting.

set -euo pipefail

LOG_DIR="/tmp/opencode-${CONTAINER_ID:-$$}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/editor-bridge.log"

log() { echo "[editor-bridge] $(date '+%T') $*" | tee -a "$LOG" >&2; }

FILEPATH="${1:-}"
if [ -z "$FILEPATH" ]; then
    log "Usage: $(basename "$0") <filepath>"
    exit 1
fi

if [ ! -f "$FILEPATH" ]; then
    log "Error: File not found: $FILEPATH"
    exit 1
fi

log "Called with: $FILEPATH"
log "URL_BRIDGE_CONFIG=${URL_BRIDGE_CONFIG:-/tmp/url-bridge/bridge.conf}"

# Copy to a host-accessible location (opencode state dir is mounted on host)
STATE_DIR="${XDG_STATE_HOME:-/root/.local/state}/opencode"
EXPORT_DIR="$STATE_DIR/exports"
mkdir -p "$EXPORT_DIR"

BASENAME=$(basename "$FILEPATH")
DEST="$EXPORT_DIR/$BASENAME"
cp "$FILEPATH" "$DEST"
log "Copied to: $DEST"

# Open on host via URL bridge
BRIDGE_CONF="${URL_BRIDGE_CONFIG:-/tmp/url-bridge/bridge.conf}"
if [ -f "$BRIDGE_CONF" ]; then
    log "Sending to host via URL bridge..."
    if /usr/local/bin/container-open-wrapper "$DEST" >> "$LOG" 2>&1; then
        log "OK — host opened the file"
    else
        log "WARN — container-open-wrapper exited non-zero (file still saved to: $DEST)"
    fi
else
    log "URL bridge not available (no bridge.conf at $BRIDGE_CONF), file saved to: $DEST"
fi

# Exit immediately — opencode reads back the (unchanged) file content
exit 0
