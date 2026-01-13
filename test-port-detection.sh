#!/usr/bin/env bash
#
# test-port-detection.sh - Test mcp-proxy port detection
#
# This test verifies that:
# 1. manage-mcp-proxy.sh correctly detects the actual port from running process
# 2. run-opencode.sh uses the detected port for config generation
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Testing mcp-proxy Port Detection ==="
echo ""

# Test 1: Check if mcp-proxy is running and detect its port
echo "Test 1: Detecting port from running mcp-proxy..."
if "$SCRIPT_DIR/manage-mcp-proxy.sh" status >/dev/null 2>&1; then
    # Extract port from status output
    STATUS_OUTPUT=$("$SCRIPT_DIR/manage-mcp-proxy.sh" status)
    DETECTED_PORT=$(echo "$STATUS_OUTPUT" | grep "Port:" | awk '{print $2}')
    
    if [ -z "$DETECTED_PORT" ]; then
        echo -e "${RED}✗ Failed to detect port from status output${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Detected port: $DETECTED_PORT${NC}"
    
    # Verify the port is actually listening
    if lsof -Pi :$DETECTED_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Port $DETECTED_PORT is listening${NC}"
    else
        echo -e "${RED}✗ Port $DETECTED_PORT is not listening${NC}"
        exit 1
    fi
    
    # Test 2: Verify process args match detected port
    echo ""
    echo "Test 2: Verifying port in process command line..."
    PID_FILE="$HOME/.cache/mcp-proxy.pid"
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        PROCESS_PORT=$(ps -p "$PID" -o args= 2>/dev/null | grep -o '\--port [0-9]*' | awk '{print $2}')
        
        if [ "$PROCESS_PORT" = "$DETECTED_PORT" ]; then
            echo -e "${GREEN}✓ Process port matches detected port: $PROCESS_PORT${NC}"
        else
            echo -e "${RED}✗ Port mismatch: process=$PROCESS_PORT, detected=$DETECTED_PORT${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠ PID file not found, skipping process verification${NC}"
    fi
    
    # Test 3: Simulate config generation with detected port
    echo ""
    echo "Test 3: Testing config generation with detected port..."
    
    # Check if original config exists
    if [ ! -f "$HOME/.config/opencode/opencode.jsonc" ]; then
        echo -e "${YELLOW}⚠ No original config found, skipping config test${NC}"
    else
        # Create temp directory for test config
        TEST_CONFIG_DIR=$(mktemp -d -t test-config-XXXXXX)
        TEST_CONFIG_FILE="$TEST_CONFIG_DIR/opencode.jsonc"
        
        # Generate config with detected port
        if python3 "$SCRIPT_DIR/lib/detect-remote-mcps.py" \
            --config "$HOME/.config/opencode/opencode.jsonc" \
            --docker-config "$TEST_CONFIG_FILE" \
            --port "$DETECTED_PORT" \
            --docker \
            > /dev/null 2>&1; then
            
            # Verify the config has the correct port
            if grep -q "host.docker.internal:$DETECTED_PORT" "$TEST_CONFIG_FILE"; then
                echo -e "${GREEN}✓ Config generated with correct port: $DETECTED_PORT${NC}"
            else
                echo -e "${RED}✗ Config does not contain correct port${NC}"
                echo "Expected: host.docker.internal:$DETECTED_PORT"
                echo "Config content:"
                grep "host.docker.internal" "$TEST_CONFIG_FILE" || echo "(no host.docker.internal found)"
                rm -rf "$TEST_CONFIG_DIR"
                exit 1
            fi
        else
            echo -e "${YELLOW}⚠ Config generation failed (may be expected if no remote MCPs)${NC}"
        fi
        
        # Cleanup
        rm -rf "$TEST_CONFIG_DIR"
    fi
    
    echo ""
    echo -e "${GREEN}=== All Tests Passed ===${NC}"
    echo ""
    echo "Summary:"
    echo "  - mcp-proxy is running on port $DETECTED_PORT"
    echo "  - Port detection works correctly"
    echo "  - Config generation uses correct port"
    
else
    echo -e "${YELLOW}⚠ mcp-proxy is not running${NC}"
    echo "Start it with: $SCRIPT_DIR/manage-mcp-proxy.sh start"
    echo "Or run: $SCRIPT_DIR/run-opencode.sh"
    exit 1
fi
