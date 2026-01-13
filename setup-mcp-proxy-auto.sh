#!/usr/bin/env bash
#
# setup-mcp-proxy-auto.sh - Automatically configure mcp-proxy for all remote MCPs
#
# This script:
# 1. Reads your ~/.config/opencode/opencode.jsonc
# 2. Detects all remote MCP servers (using mcp-remote)
# 3. Creates ~/.config/opencode-docker/ with modified config
# 4. Generates mcp-proxy config for all remote servers
# 5. Restarts mcp-proxy with new config
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Automatic MCP Proxy Setup ===${NC}"
echo ""
echo "This will:"
echo "  1. Scan your OpenCode config for remote MCP servers"
echo "  2. Create a Docker-specific config at ~/.config/opencode-docker/"
echo "  3. Generate mcp-proxy configuration"
echo "  4. Restart mcp-proxy with all remote servers"
echo ""
echo -e "${YELLOW}Your original config will NOT be modified${NC}"
echo ""

# Check if Python script exists
if [ ! -f "$SCRIPT_DIR/lib/detect-remote-mcps.py" ]; then
    echo -e "${RED}✗ lib/detect-remote-mcps.py not found${NC}"
    exit 1
fi

# Run detection in dry-run mode first to show what will happen
echo "Analyzing your configuration..."
echo ""

if ! python3 "$SCRIPT_DIR/lib/detect-remote-mcps.py" --dry-run; then
    echo ""
    echo -e "${RED}✗ Failed to analyze configuration${NC}"
    exit 1
fi

echo ""
read -p "Proceed with setup? [y/N]: " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Cancelled"
    exit 0
fi

echo ""
echo "Setting up mcp-proxy..."

# Run the actual setup
if ! python3 "$SCRIPT_DIR/lib/detect-remote-mcps.py"; then
    echo ""
    echo -e "${RED}✗ Setup failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Configuration complete!${NC}"
echo ""

# Restart mcp-proxy with new config
echo "Restarting mcp-proxy..."
if "$SCRIPT_DIR/manage-mcp-proxy.sh" restart; then
    echo -e "${GREEN}✓ mcp-proxy restarted successfully${NC}"
else
    echo -e "${YELLOW}⚠ mcp-proxy restart failed - check logs${NC}"
    echo "  View logs: ./manage-mcp-proxy.sh logs"
fi

echo ""
echo -e "${GREEN}=== Setup Complete! ===${NC}"
echo ""
echo "Configuration:"
echo "  Original config: ~/.config/opencode/opencode.jsonc (unchanged)"
echo "  Docker config:   ~/.config/opencode-docker/opencode.jsonc (modified)"
echo "  mcp-proxy config: ~/.cache/mcp-proxy-config.json"
echo ""
echo "Next steps:"
echo "  1. Run OpenCode in Docker:"
echo -e "     ${BLUE}./run-opencode-with-oauth.sh${NC}"
echo ""
echo "  2. Test your remote MCPs (e.g., Linear):"
echo "     Ask: 'List my Linear issues'"
echo ""
echo "Management:"
echo "  Check status:  ./manage-mcp-proxy.sh status"
echo "  View logs:     ./manage-mcp-proxy.sh logs"
echo "  Restart:       ./manage-mcp-proxy.sh restart"
echo ""
