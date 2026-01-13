#!/usr/bin/env bash
#
# debug.sh - Quick debug helper for OAuth setup
#

set -euo pipefail

echo "=== OpenCode Docker OAuth Debug ==="
echo ""

echo "1. mcp-proxy Status:"
./manage-mcp-proxy.sh status || echo "  Not running"
echo ""

echo "2. Config Files:"
echo "  Original: ~/.config/opencode/opencode.jsonc"
if [ -f ~/.config/opencode/opencode.jsonc ]; then
    echo "    ✓ Exists"
else
    echo "    ✗ Missing"
fi

echo "  Docker: ~/.config/opencode-docker/opencode.jsonc"
if [ -f ~/.config/opencode-docker/opencode.jsonc ]; then
    echo "    ✓ Exists"
else
    echo "    ✗ Missing (run ./setup-mcp-proxy-auto.sh)"
fi

echo "  Proxy: ~/.cache/mcp-proxy-config.json"
if [ -f ~/.cache/mcp-proxy-config.json ]; then
    echo "    ✓ Exists"
else
    echo "    ✗ Missing (run ./setup-mcp-proxy-auto.sh)"
fi
echo ""

echo "3. Detected Remote MCPs:"
python3 lib/detect-remote-mcps.py --dry-run 2>&1 | grep -A 10 "Detecting remote" || echo "  Error detecting"
echo ""

echo "4. Docker Config (Linear):"
if [ -f ~/.config/opencode-docker/opencode.jsonc ]; then
    grep -A 5 '"linear"' ~/.config/opencode-docker/opencode.jsonc || echo "  Linear not found"
else
    echo "  Docker config not found"
fi
echo ""

echo "5. Test Docker Connectivity:"
if docker run --rm curlimages/curl curl -s -o /dev/null -w "%{http_code}" http://host.docker.internal:8080/ 2>/dev/null | grep -q "404"; then
    echo "  ✓ Can reach mcp-proxy from Docker"
else
    echo "  ✗ Cannot reach mcp-proxy from Docker"
fi
echo ""

echo "6. Recent Logs (last 10 lines):"
if [ -f ~/.cache/mcp-proxy.log ]; then
    tail -10 ~/.cache/mcp-proxy.log
else
    echo "  No logs found"
fi
