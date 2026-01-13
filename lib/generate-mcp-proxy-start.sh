#!/usr/bin/env bash
#
# generate-mcp-proxy-start.sh - Generate mcp-proxy start command from config
#
# This reads the detected remote MCPs and generates the appropriate
# mcp-proxy command with multiple --named-server arguments
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXY_PORT="${PROXY_PORT:-8080}"
PROXY_HOST="${PROXY_HOST:-0.0.0.0}"

# Read the mcp-proxy config
CONFIG_FILE="$HOME/.cache/mcp-proxy-config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found: $CONFIG_FILE" >&2
    echo "Run: python3 detect-remote-mcps.py" >&2
    exit 1
fi

# Parse JSON and generate --named-server arguments
NAMED_SERVERS=$(python3 << PYEOF
import json
import sys
import os

config_file = os.path.expanduser('$CONFIG_FILE')

try:
    with open(config_file) as f:
        config = json.load(f)
    
    servers = config.get('mcpServers', {})
    
    args = []
    for name, server_config in servers.items():
        command = server_config.get('command', '')
        if command:
            args.append(f'--named-server {name} "{command}"')
    
    print(' '.join(args))
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
)

if [ -z "$NAMED_SERVERS" ]; then
    echo "Error: No named servers found in config" >&2
    exit 1
fi

# Generate and execute the command
CMD="mcp-proxy $NAMED_SERVERS --port $PROXY_PORT --host $PROXY_HOST --allow-origin '*'"

echo "Generated command:"
echo "$CMD"
echo ""

# Execute it
eval exec $CMD
