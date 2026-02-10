#!/usr/bin/env bash
#
# This script:
# 1. Ensures mcp-proxy is running on the Mac host
# 2. Starts the URL bridge for browser opening
# 3. Runs OpenCode in Docker with proper configuration
#
# Usage:
#   ./run-opencode.sh [opencode arguments]
#   ./run-opencode.sh enter              # Enter a running container (with fzf selection)
#   ./run-opencode.sh logs [options]     # View container logs (e.g., logs -f --tail 100)
#
# Environment Variables:
#   DOCKER_ENV    Comma/space-separated list of env vars to pass through
#                 Examples: "AWS_PROFILE,DEBUG=1" or "VAR1 VAR2=value"
#
# Examples:
#   DOCKER_ENV="AWS_PROFILE,DEBUG=1" ./run-opencode.sh
#   ./run-opencode.sh enter
#   ./run-opencode.sh logs -f --tail 50
#

set -euo pipefail

# Check if we're running inside a Docker container
if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
    echo "ERROR: This script must be run from the HOST, not from inside a container."
    echo ""
    echo "If you're inside an OpenCode container, exit first and run this script from your Mac terminal."
    echo ""
    echo "To exit the container, press Ctrl+D or type 'exit'"
    exit 1
fi

# Check if docker command is available
if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker command not found. Please install Docker Desktop."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-opencode-dev:latest}"
PROXY_PORT="${PROXY_PORT:-8080}"

# Optional features (set to "true" to enable)
ENABLE_GIT_CREDENTIAL_PROXY="${ENABLE_GIT_CREDENTIAL_PROXY:-false}"

# Parse DOCKER_ENV for environment variables to pass through
# Format: "VAR1,VAR2,VAR3=value" or "VAR1 VAR2 VAR3=value"
declare -a PASSTHROUGH_ENV_VARS=()
if [ -n "${DOCKER_ENV:-}" ]; then
    # Split on both comma and space
    IFS=', ' read -ra ENV_ITEMS <<< "$DOCKER_ENV"
    for item in "${ENV_ITEMS[@]}"; do
        item=$(echo "$item" | xargs)  # trim whitespace
        if [ -n "$item" ]; then
            PASSTHROUGH_ENV_VARS+=("$item")
        fi
    done
fi

# Function to check if a port is available
is_port_available() {
    local port=$1
    ! lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1
}

# Function to find an available port starting from a given port
find_available_port() {
    local start_port=$1
    local port=$start_port
    while [ $port -lt $((start_port + 100)) ]; do
        if is_port_available $port; then
            echo $port
            return 0
        fi
        port=$((port + 1))
    done
    return 1
}

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
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Show usage information
show_usage() {
    echo "OpenCode Docker - Run OpenCode in isolated containers"
    echo ""
    echo "Usage:"
    echo "  $0                        Start OpenCode in a new container"
    echo "  $0 enter                  Enter a running container (interactive selection)"
    echo "  $0 logs [options]         View container logs (e.g., -f --tail 100)"
    echo "  $0 ps                     List running containers"
    echo "  $0 stop                   Stop a running container (interactive selection)"
    echo "  $0 help                   Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  DOCKER_ENV               Comma/space-separated env vars to pass through"
    echo "  PROXY_PORT               MCP proxy port (default: 8080)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Start OpenCode"
    echo "  $0 enter                              # Enter a container"
    echo "  $0 logs -f --tail 50                  # Follow logs with last 50 lines"
    echo "  $0 stop                               # Stop a container"
    echo "  DOCKER_ENV='AWS_PROFILE' $0           # Pass AWS_PROFILE to container"
    exit 0
}

# Show help
if [ "${1:-}" = "help" ] || [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    show_usage
fi

# Handle "ps" command to list running containers
if [ "${1:-}" = "ps" ] || [ "${1:-}" = "list" ]; then
    containers=$(docker ps --filter "name=^opencode-" --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}\t{{.Size}}" 2>/dev/null)
    
    if [ -z "$containers" ] || [ "$(echo "$containers" | wc -l)" -eq 1 ]; then
        echo -e "${YELLOW}No running opencode containers found${NC}"
        exit 0
    fi
    
    echo -e "${GREEN}Running OpenCode containers:${NC}"
    echo "$containers"
    exit 0
fi

# Function to list all running opencode containers with fzf
list_and_select_container() {
    local containers
    containers=$(docker ps --filter "name=^opencode-" --format "{{.Names}}\t{{.Status}}\t{{.RunningFor}}" 2>/dev/null)
    
    if [ -z "$containers" ]; then
        echo -e "${RED}Error: No running opencode containers found${NC}"
        echo "Run './run-opencode.sh' first to start a container"
        exit 1
    fi
    
    local container_count
    container_count=$(echo "$containers" | wc -l | xargs)
    
    if [ "$container_count" -eq 1 ]; then
        # Only one container, use it directly
        echo "$containers" | awk '{print $1}'
    else
        # Multiple containers, use fzf if available
        if command -v fzf >/dev/null 2>&1; then
            echo "$containers" | fzf --height=~10 --header="Select container to enter:" | awk '{print $1}'
        else
            echo -e "${YELLOW}Multiple containers found. fzf not installed, showing list:${NC}"
            echo "$containers" | nl
            echo -n "Enter number: "
            read -r selection
            echo "$containers" | sed -n "${selection}p" | awk '{print $1}'
        fi
    fi
}

# Handle "enter" command to exec into existing container
if [ "${1:-}" = "enter" ]; then
    CONTAINER_NAME=$(list_and_select_container)
    if [ -n "$CONTAINER_NAME" ]; then
        echo -e "${GREEN}Entering container: $CONTAINER_NAME${NC}"
        exec docker exec -it "$CONTAINER_NAME" bash
    else
        echo -e "${RED}No container selected${NC}"
        exit 1
    fi
fi

# Handle "logs" command to view container logs
if [ "${1:-}" = "logs" ]; then
    CONTAINER_NAME=$(list_and_select_container)
    if [ -n "$CONTAINER_NAME" ]; then
        echo -e "${GREEN}Showing logs for: $CONTAINER_NAME${NC}"
        shift  # Remove 'logs' argument
        exec docker logs "$@" "$CONTAINER_NAME"
    else
        echo -e "${RED}No container selected${NC}"
        exit 1
    fi
fi

# Handle "stop" command to stop a running container
if [ "${1:-}" = "stop" ]; then
    CONTAINER_NAME=$(list_and_select_container)
    if [ -n "$CONTAINER_NAME" ]; then
        echo -e "${YELLOW}Stopping container: $CONTAINER_NAME${NC}"
        docker stop "$CONTAINER_NAME"
        echo -e "${GREEN}Container stopped${NC}"
    else
        echo -e "${RED}No container selected${NC}"
        exit 1
    fi
    exit 0
fi

echo -e "${GREEN}=== OpenCode Docker with OAuth Support ===${NC}"
echo ""

# Step 1: Check/start mcp-proxy on host (Handles MCP OAuth callbacks)
echo "Checking mcp-proxy service..."

# First check if mcp-proxy is already running
if "$SCRIPT_DIR/manage-mcp-proxy.sh" status >/dev/null 2>&1; then
    # Detect actual port from running process
    PID_FILE="$HOME/.cache/mcp-proxy.pid"
    if [ -f "$PID_FILE" ]; then
        RUNNING_PID=$(cat "$PID_FILE")
        ACTUAL_PORT=$(ps -p "$RUNNING_PID" -o args= 2>/dev/null | grep -o '\--port [0-9]*' | awk '{print $2}')
        if [ -n "$ACTUAL_PORT" ]; then
            PROXY_PORT=$ACTUAL_PORT
            export PROXY_PORT
            echo -e "${GREEN}✓ mcp-proxy is running on port $PROXY_PORT${NC}"
        else
            echo -e "${GREEN}✓ mcp-proxy is running on port $PROXY_PORT (assumed)${NC}"
        fi
    else
        echo -e "${GREEN}✓ mcp-proxy is running on port $PROXY_PORT (assumed)${NC}"
    fi
else
    # Check if the requested port is available
    if ! is_port_available $PROXY_PORT; then
        # Check if it's mcp-proxy using the port
        if lsof -Pi :$PROXY_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
            PORT_PID=$(lsof -Pi :$PROXY_PORT -sTCP:LISTEN -t 2>/dev/null | head -1)
            if ps -p "$PORT_PID" -o command= 2>/dev/null | grep -q "mcp-proxy"; then
                echo -e "${GREEN}✓ mcp-proxy already running on port $PROXY_PORT${NC}"
            else
                echo -e "${YELLOW}⚠ Port $PROXY_PORT is in use by another process (PID $PORT_PID)${NC}"
                echo "  Finding alternative port..."
                PROXY_PORT=$(find_available_port $((PROXY_PORT + 1)))
                if [ -z "$PROXY_PORT" ]; then
                    echo -e "${RED}✗ Could not find an available port${NC}"
                    exit 1
                fi
                echo -e "${GREEN}  Using port $PROXY_PORT instead${NC}"
                export PROXY_PORT
            fi
        fi
    fi
    
    # Try to start mcp-proxy if not running
    if ! "$SCRIPT_DIR/manage-mcp-proxy.sh" status >/dev/null 2>&1; then
        echo -e "${YELLOW}Starting mcp-proxy on Mac host (port $PROXY_PORT)...${NC}"
        if ! "$SCRIPT_DIR/manage-mcp-proxy.sh" start; then
            echo -e "${RED}✗ Failed to start mcp-proxy${NC}"
            echo "  Try manually: PROXY_PORT=$PROXY_PORT $SCRIPT_DIR/manage-mcp-proxy.sh start"
            exit 1
        fi
    fi
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

# Function to validate JSON/JSONC file
validate_jsonc() {
    local file="$1"
    # Try to parse with Python (strips comments and validates)
    python3 -c "
import json
import re
import sys

try:
    with open('$file', 'r') as f:
        content = f.read()
    # Strip comments (simple approach for JSONC)
    # Only strip // comments that are preceded by whitespace or start of line
    content = re.sub(r'(?:^|(?<=\s))//.*', '', content, flags=re.MULTILINE)
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
    # Remove trailing commas before closing braces/brackets
    content = re.sub(r',(\s*[}\]])', r'\1', content)
    json.loads(content)
    sys.exit(0)
except Exception as e:
    print(f'Invalid JSON/JSONC: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1
}

# Copy the entire config directory structure (agents, skills, commands, etc.)
if [ -d "$HOME/.config/opencode" ]; then
    # Copy everything except opencode.jsonc (we'll generate that)
    rsync -a --exclude='opencode.jsonc' "$HOME/.config/opencode/" "$TEMP_CONFIG_DIR/" 2>/dev/null || \
        cp -r "$HOME/.config/opencode/"* "$TEMP_CONFIG_DIR/" 2>/dev/null || true
    
    # Translate the config to use mcp-proxy on host
    if [ -f "$HOME/.config/opencode/opencode.jsonc" ]; then
        # Validate the config file first
        if ! validate_jsonc "$HOME/.config/opencode/opencode.jsonc"; then
            echo -e "${RED}✗ Error: opencode.jsonc is invalid!${NC}"
            echo -e "${RED}  File: $HOME/.config/opencode/opencode.jsonc${NC}"
            echo ""
            echo "Please fix the JSON syntax errors before starting OpenCode."
            echo "Common issues:"
            echo "  - Missing or extra commas"
            echo "  - Unclosed brackets or braces"
            echo "  - Invalid escape sequences"
            echo ""
            rm -rf "$TEMP_CONFIG_DIR"
            exit 1
        fi
        
        # Config is valid, proceed with translation
        TRANSLATION_ERROR=""
        if ! python3 "$SCRIPT_DIR/lib/detect-remote-mcps.py" \
            --config "$HOME/.config/opencode/opencode.jsonc" \
            --output "$HOME/.cache/mcp-proxy-config.json" \
            --docker-config "$TEMP_CONFIG_FILE" \
            --port "$PROXY_PORT" \
            --docker \
            2>&1 | tee /tmp/config-translation-error.log; then
            TRANSLATION_ERROR=$(cat /tmp/config-translation-error.log)
        fi
        
        if [ -n "$TRANSLATION_ERROR" ] || [ ! -f "$TEMP_CONFIG_FILE" ]; then
            echo -e "${RED}✗ Config translation failed!${NC}"
            echo -e "${RED}Error:${NC}"
            echo "$TRANSLATION_ERROR" | head -10
            echo ""
            echo "Cannot start OpenCode with broken config translation."
            rm -rf "$TEMP_CONFIG_DIR"
            exit 1
        fi
        
        echo -e "${GREEN}✓ Config validated and translated for Docker${NC}"
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
    -v "$TEMP_CONFIG_DIR:/root/.config/opencode"
    -v "$PWD:$PWD"
    -w "${PWD:-/root}"
    --name "$CONTAINER_NAME"
    # Persistent Python virtual environments (avoids host/container .venv conflicts)
    # -v "$VENV_CACHE_DIR/poetry:/root/.cache/pypoetry/virtualenvs"
    # -v "$VENV_CACHE_DIR/uv:/root/.cache/uv/venvs"
)

# Generate unique container ID from container name (to avoid conflicts when sharing /tmp)
# Extract numeric suffix from container name (e.g., "opencode-myproject-12345" -> "12345")
CONTAINER_ID=$(echo "$CONTAINER_NAME" | grep -o '[0-9]*$' || echo "$$")
DOCKER_ARGS+=(-e "CONTAINER_ID=$CONTAINER_ID")

# Set fake DISPLAY for clipboard tools (will be overridden by entrypoint to unique value)
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

# Pass through user-specified environment variables (-e flags)
if [ ${#PASSTHROUGH_ENV_VARS[@]} -gt 0 ]; then
    echo -e "  Custom env vars:"
    for env_var in "${PASSTHROUGH_ENV_VARS[@]}"; do
        if [[ "$env_var" == *"="* ]]; then
            # Explicit value provided: -e VAR=value
            var_name="${env_var%%=*}"
            DOCKER_ARGS+=(-e "$env_var")
            echo -e "    ${GREEN}$var_name${NC} (explicit value)"
        else
            # No value provided: -e VAR (get from current environment)
            if [ -n "${!env_var:-}" ]; then
                DOCKER_ARGS+=(-e "$env_var=${!env_var}")
                echo -e "    ${GREEN}$env_var${NC} (from host)"
            else
                echo -e "    ${YELLOW}$env_var${NC} (not set, skipped)"
            fi
        fi
    done
fi

# Mount SSH agent socket for git operations
# On macOS with Docker Desktop, use the special /run/host-services path
# which is more reliable than mounting the launchd socket directly
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS with Docker Desktop - use the built-in SSH agent forwarding
    DOCKER_ARGS+=(
        -v "/run/host-services/ssh-auth.sock:/ssh-agent"
        -e "SSH_AUTH_SOCK=/ssh-agent"
    )
    echo -e "  SSH agent: ${GREEN}forwarded (Docker Desktop)${NC}"
elif [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
    # Linux - mount the host socket directly
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
