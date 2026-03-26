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

FILEPATH="${1:-}"
if [ -z "$FILEPATH" ]; then
    echo "Usage: $(basename "$0") <filepath>" >&2
    exit 1
fi

if [ ! -f "$FILEPATH" ]; then
    echo "Error: File not found: $FILEPATH" >&2
    exit 1
fi

# Copy to a host-accessible location (opencode state dir is mounted on host)
STATE_DIR="${XDG_STATE_HOME:-/root/.local/state}/opencode"
EXPORT_DIR="$STATE_DIR/exports"
mkdir -p "$EXPORT_DIR"

BASENAME=$(basename "$FILEPATH")
DEST="$EXPORT_DIR/$BASENAME"
cp "$FILEPATH" "$DEST"

# Open on host via URL bridge
if [ -f "${URL_BRIDGE_CONFIG:-/tmp/url-bridge/bridge.conf}" ]; then
    /usr/local/bin/container-open-wrapper "$DEST" 2>/dev/null || true
else
    echo "[editor-bridge] URL bridge not available, file saved to: $DEST" >&2
fi

# Exit immediately — opencode reads back the (unchanged) file content
exit 0
