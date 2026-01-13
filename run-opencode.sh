#!/usr/bin/env bash
#
# This script:
# 1. Ensures mcp-proxy is running on the Mac host
# 2. Starts the URL bridge for browser opening
# 3. Runs OpenCode in Docker with proper configuration
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-opencode-dev:latest}"
PROXY_PORT="${PROXY_PORT:-8080}"

# Optional features (set to "true" to enable)
ENABLE_GIT_CREDENTIAL_PROXY="${ENABLE_GIT_CREDENTIAL_PROXY:-false}"

# Persistent storage for container Python virtual environments (XDG cache)
VENV_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/opencode/docker-venvs"
mkdir -p "$VENV_CACHE_DIR/poetry" "$VENV_CACHE_DIR/uv"

# Function to generate container name based on current directory
get_container_name() {
    local folder_name=$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/^-*//' | sed 's/-*$//')
    echo "opencode-$folder_name-${RANDOM}"
}

# Function to find running container for current directory
find_running_container() {
    local folder_name=$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/^-*//' | sed 's/-*$//')
    docker ps --filter "name=^opencode-$folder_name-" --format '{{.Names}}' | head -1
}

# Optional user-specific directory mounts (set via environment variables)
# Format: "host_path:container_path" or "host_path:container_path:options"
OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-}"
EXTRA_MOUNTS="${EXTRA_MOUNTS:-}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Handle "enter" command to exec into existing container
if [ "${1:-}" = "enter" ]; then
    CONTAINER_NAME=$(find_running_container)
    if [ -n "$CONTAINER_NAME" ]; then
        echo -e "${GREEN}Entering container: $CONTAINER_NAME${NC}"
        exec docker exec -it "$CONTAINER_NAME" bash
    else
        FOLDER_NAME=$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/^-*//' | sed 's/-*$//')
        echo -e "${RED}Error: No running container found for this project${NC}"
        echo "Expected container pattern: opencode-$FOLDER_NAME-*"
        echo "Run './run-opencode.sh' first to start the container"
        exit 1
    fi
fi

echo -e "${GREEN}=== OpenCode Docker with OAuth Support ===${NC}"
echo ""

# Step 1: Check/start mcp-proxy on host (Handles MCP OAuth callbacks)
echo "Checking mcp-proxy service..."
if ! "$SCRIPT_DIR/manage-mcp-proxy.sh" status >/dev/null 2>&1; then
    echo -e "${YELLOW}Starting mcp-proxy on Mac host...${NC}"
    if ! "$SCRIPT_DIR/manage-mcp-proxy.sh" start; then
        echo -e "${RED}✗ Failed to start mcp-proxy${NC}"
        echo "  Try manually: $SCRIPT_DIR/manage-mcp-proxy.sh start"
        exit 1
    fi
else
    echo -e "${GREEN}✓ mcp-proxy is running${NC}"
fi
echo ""

# Step 2: Start clipboard bridge (Handles macOS clipboard → container paste)
# Uses a persistent shared directory so multiple instances share one daemon
echo "Checking clipboard bridge..."
CLIPBOARD_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/opencode/clipboard-bridge"

# Use the management script to ensure it's running
if ! "$SCRIPT_DIR/lib/manage-clipboard-bridge.sh" status >/dev/null 2>&1; then
    echo -e "${YELLOW}Starting clipboard bridge...${NC}"
    if ! "$SCRIPT_DIR/lib/manage-clipboard-bridge.sh" start; then
        echo -e "${YELLOW}⚠ Failed to start clipboard bridge (Ctrl+V paste may not work)${NC}"
        # Don't fail - clipboard is optional
    fi
else
    echo -e "${GREEN}✓ Clipboard bridge is running${NC}"
fi

# Verify clipboard files exist
CLIPBOARD_READY=false
if [ -f "$CLIPBOARD_DIR/clipboard.mime" ]; then
    CLIPBOARD_READY=true
    echo -e "${GREEN}✓ Clipboard bridge ready${NC}"
else
    echo -e "${YELLOW}⚠ Clipboard bridge not ready (Ctrl+V paste may not work)${NC}"
    # Don't fail - clipboard is optional
fi
echo ""

# Step 2.5: Start git credential proxy (Handles macOS Keychain → container git)
# Only if enabled via environment variable
GIT_CRED_SOCKET="/tmp/git-credential-proxy.sock"
GIT_CRED_PID=""
GIT_CRED_ENABLED=false

if [ "$ENABLE_GIT_CREDENTIAL_PROXY" = "true" ]; then
    echo "Checking git credential proxy..."
    
    start_git_credential_proxy() {
        # Check if already running
        if [ -S "$GIT_CRED_SOCKET" ]; then
            # Test if it's responsive
            if timeout 1 bash -c "echo -n '' > /dev/tcp/localhost/0 2>/dev/null" 2>/dev/null || \
               python3 -c "import socket; s=socket.socket(socket.AF_UNIX); s.connect('$GIT_CRED_SOCKET'); s.close()" 2>/dev/null; then
                echo -e "${GREEN}✓ Git credential proxy already running${NC}"
                GIT_CRED_ENABLED=true
                return 0
            else
                # Socket exists but not responsive, clean it up
                rm -f "$GIT_CRED_SOCKET"
            fi
        fi
        
        # Start the proxy
        python3 "$SCRIPT_DIR/lib/git-credential-proxy.py" "$GIT_CRED_SOCKET" >/dev/null 2>&1 &
        GIT_CRED_PID=$!
        
        # Wait for socket to be created
        for i in {1..10}; do
            if [ -S "$GIT_CRED_SOCKET" ]; then
                echo -e "${GREEN}✓ Git credential proxy started${NC}"
                GIT_CRED_ENABLED=true
                return 0
            fi
            if ! kill -0 "$GIT_CRED_PID" 2>/dev/null; then
                echo -e "${YELLOW}⚠ Git credential proxy failed to start (git operations may prompt for credentials)${NC}"
                GIT_CRED_PID=""
                return 1
            fi
            sleep 0.5
        done
        
        echo -e "${YELLOW}⚠ Git credential proxy timeout (git operations may prompt for credentials)${NC}"
        return 1
    }
    
    start_git_credential_proxy
    echo ""
else
    echo -e "${YELLOW}Git credential proxy disabled (set ENABLE_GIT_CREDENTIAL_PROXY=true to enable)${NC}"
    echo ""
fi

cleanup_git_credential_proxy() {
    if [ -n "$GIT_CRED_PID" ] && kill -0 "$GIT_CRED_PID" 2>/dev/null; then
        kill "$GIT_CRED_PID" 2>/dev/null || true
        wait "$GIT_CRED_PID" 2>/dev/null || true
    fi
}

# Step 3: Start URL bridge for browser opening (Handles generic CLI tool redirects)
echo "Starting URL bridge for browser opening..."
BRIDGE_DIR=""
BRIDGE_PID=""

cleanup_bridge() {
    if [ -n "$BRIDGE_PID" ] && kill -0 "$BRIDGE_PID" 2>/dev/null; then
        kill "$BRIDGE_PID" 2>/dev/null || true
        wait "$BRIDGE_PID" 2>/dev/null || true
    fi
    
    if [ -n "$BRIDGE_DIR" ] && [ -d "$BRIDGE_DIR" ]; then
        rm -rf "$BRIDGE_DIR"
    fi
}

CONTAINER_NAME=$(get_container_name)

# Create temporary directory for bridge config
BRIDGE_DIR=$(mktemp -d -t url-bridge-XXXXXX)

# Start host URL opener service
python3 "$SCRIPT_DIR/lib/host-url-opener.py" "$BRIDGE_DIR" 2>/dev/null &
BRIDGE_PID=$!

# Wait for config file to be created
for i in {1..10}; do
    if [ -f "$BRIDGE_DIR/bridge.conf" ]; then
        echo -e "${GREEN}✓ URL bridge started${NC}"
        break
    fi
    if ! kill -0 "$BRIDGE_PID" 2>/dev/null; then
        echo -e "${YELLOW}⚠ URL bridge failed (OAuth browser opening may not work)${NC}"
        BRIDGE_DIR=""
        BRIDGE_PID=""
        break
    fi
    sleep 0.5
done
echo ""

# Step 4: Generate translated config for Docker
echo "Generating Docker-specific config..."
TEMP_CONFIG_DIR=$(mktemp -d -t opencode-config-XXXXXX)
TEMP_CONFIG_FILE="$TEMP_CONFIG_DIR/opencode.jsonc"

# Copy the entire config directory structure (agents, skills, commands, etc.)
if [ -d "$HOME/.config/opencode" ]; then
    # Copy everything except opencode.jsonc (we'll generate that)
    rsync -a --exclude='opencode.jsonc' "$HOME/.config/opencode/" "$TEMP_CONFIG_DIR/" 2>/dev/null || \
        cp -r "$HOME/.config/opencode/"* "$TEMP_CONFIG_DIR/" 2>/dev/null || true
    
    # Translate the config to use mcp-proxy on host
    if [ -f "$HOME/.config/opencode/opencode.jsonc" ]; then
        python3 "$SCRIPT_DIR/lib/detect-remote-mcps.py" \
            --config "$HOME/.config/opencode/opencode.jsonc" \
            --output "$HOME/.cache/mcp-proxy-config.json" \
            --docker-config "$TEMP_CONFIG_FILE" \
            --port "$PROXY_PORT" \
            --docker \
            > /dev/null 2>&1 || {
                echo -e "${YELLOW}⚠ Config translation failed, using original config${NC}"
                cp "$HOME/.config/opencode/opencode.jsonc" "$TEMP_CONFIG_FILE"
            }
        echo -e "${GREEN}✓ Config translated for Docker (with agents/skills)${NC}"
    else
        echo -e "${YELLOW}⚠ No opencode.jsonc found, using directory structure only${NC}"
        echo '{}' > "$TEMP_CONFIG_FILE"
    fi
else
    echo -e "${YELLOW}⚠ No config directory found at ~/.config/opencode${NC}"
    mkdir -p "$TEMP_CONFIG_DIR"
    echo '{}' > "$TEMP_CONFIG_FILE"
fi
echo ""

# Add temp config cleanup to trap
cleanup_config() {
    if [ -n "$TEMP_CONFIG_DIR" ] && [ -d "$TEMP_CONFIG_DIR" ]; then
        rm -rf "$TEMP_CONFIG_DIR"
    fi
}

cleanup_all() {
    echo ""
    echo "Cleaning up..."
    cleanup_bridge
    cleanup_git_credential_proxy
    cleanup_config
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}

trap cleanup_all EXIT INT TERM

# Step 5: Build docker command
echo "Starting OpenCode in Docker..."
echo -e "  Image: ${GREEN}$IMAGE${NC}"
echo -e "  OAuth proxy: ${GREEN}host.docker.internal:$PROXY_PORT${NC}"
if [ "$CLIPBOARD_READY" = true ]; then
    echo -e "  Clipboard: ${GREEN}macOS → container (shared)${NC}"
fi
echo ""

# No need to clean up - random suffix prevents collisions

DOCKER_ARGS=(
    -it
    --rm
    -v "$HOME/.cache/opencode:/root/.cache/opencode"
    -v "$HOME/.local/state/opencode:/root/.local/state/opencode"
    -v "$HOME/.local/share/opencode:/root/.local/share/opencode"
    -v "$HOME/.cache/opencode-docker/:/root/.cache"
    # -v "$HOME/.gitconfig:/root/.gitconfig"
    -v "$TEMP_CONFIG_DIR:/root/.config/opencode:ro"
    -v "$PWD:$PWD"
    -w "${PWD:-/root}"
    --name "$CONTAINER_NAME"
    # Persistent Python virtual environments (avoids host/container .venv conflicts)
    # -v "$VENV_CACHE_DIR/poetry:/root/.cache/pypoetry/virtualenvs"
    # -v "$VENV_CACHE_DIR/uv:/root/.cache/uv/venvs"
)

# Set fake DISPLAY for clipboard tools (xsel requires it)
DOCKER_ARGS+=(-e "DISPLAY=:99")

# Pass through TERM for proper terminal features (clipboard, colors, etc.)
# Default to xterm-256color if not set
DOCKER_ARGS+=(-e "TERM=${TERM:-xterm-256color}")
DOCKER_ARGS+=(-e "COLORTERM=${COLORTERM:-truecolor}")

# Pass through common authentication environment variables
# These are used by various CLI tools (gh, etc.)
if [ -n "${GH_TOKEN:-}" ]; then
    DOCKER_ARGS+=(-e "GH_TOKEN=$GH_TOKEN")
fi
if [ -n "${GITHUB_TOKEN:-}" ]; then
    DOCKER_ARGS+=(-e "GITHUB_TOKEN=$GITHUB_TOKEN")
fi

# Mount SSH agent socket for git operations
if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
    DOCKER_ARGS+=(
        -v "$SSH_AUTH_SOCK:/ssh-agent"
        -e "SSH_AUTH_SOCK=/ssh-agent"
    )
    echo -e "  SSH agent: ${GREEN}forwarded${NC}"
fi

# Mount git credential proxy socket if enabled
if [ "$GIT_CRED_ENABLED" = true ] && [ -S "$GIT_CRED_SOCKET" ]; then
    DOCKER_ARGS+=(
        -v "$GIT_CRED_SOCKET:$GIT_CRED_SOCKET"
        -e "GIT_CREDENTIAL_SOCK=$GIT_CRED_SOCKET"
    )
    echo -e "  Git credentials: ${GREEN}macOS Keychain (via proxy)${NC}"
fi

# Mount git config (read-only) for user identity
if [ -f "$HOME/.gitconfig" ]; then
    DOCKER_ARGS+=(-v "$HOME/.gitconfig:/root/.gitconfig:ro")
    echo -e "  Git config: ${GREEN}mounted (read-only)${NC}"
fi

# Add optional user-specific mounts if environment variables are set
if [ -n "$OPENCODE_CONFIG_DIR" ]; then
    DOCKER_ARGS+=(-v "$OPENCODE_CONFIG_DIR:/root/.config/opencode")
    echo -e "  Config override: ${GREEN}$OPENCODE_CONFIG_DIR${NC}"
fi

# Add extra mounts from EXTRA_MOUNTS (comma or space separated)
if [ -n "$EXTRA_MOUNTS" ]; then
    IFS=',' read -ra MOUNTS <<< "$EXTRA_MOUNTS"
    for mount in "${MOUNTS[@]}"; do
        mount=$(echo "$mount" | xargs)  # trim whitespace
        if [ -n "$mount" ]; then
            DOCKER_ARGS+=(-v "$mount")
            echo -e "  Extra mount: ${GREEN}$mount${NC}"
        fi
    done
fi

# Add clipboard bridge volume (always mount the persistent directory)
DOCKER_ARGS+=(
    -v "${CLIPBOARD_DIR}:/shared:ro"
)

# Add URL bridge volume and env var if bridge started successfully
if [ -n "$BRIDGE_DIR" ] && [ -d "$BRIDGE_DIR" ]; then
    DOCKER_ARGS+=(
        -v "${BRIDGE_DIR}:/tmp/url-bridge:ro"
        -e "URL_BRIDGE_CONFIG=/tmp/url-bridge/bridge.conf"
    )
fi

echo ""
echo -e "${GREEN}Launching OpenCode...${NC}"
echo ""
echo -e "${YELLOW}Note: If you authenticate CLI tools (gh, etc.) after starting,${NC}"
echo -e "${YELLOW}      you'll need to restart the container to use them.${NC}"
echo ""

# Run docker with TTY-preserving entrypoint
echo "[Host] Executing docker run command..."
docker run "${DOCKER_ARGS[@]}" "$IMAGE" opencode-entrypoint-tty "$@"

# Cleanup happens automatically via trap
