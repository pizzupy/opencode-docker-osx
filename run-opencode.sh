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

# Sanitized project name derived from the current directory (used for container
# naming and per-project volume paths to avoid cross-session lock conflicts)
PROJECT_NAME=$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/^-*//' | sed 's/-*$//')
mkdir -p "$HOME/.local/state/opencode/$PROJECT_NAME"

# Function to generate container name based on current directory
get_container_name() {
    echo "opencode-$PROJECT_NAME-${RANDOM}"
}

# Function to find running container for current directory
find_running_container() {
    docker ps --filter "name=^opencode-$PROJECT_NAME-" --format '{{.Names}}' | head -1
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
    echo "  $0 help                   Show this help message (use 'help', not --help)"
    echo ""
    echo "Environment Variables:"
    echo "  DOCKER_ENV               Comma/space-separated env vars to pass through"
    echo "  PROXY_PORT               MCP proxy port (default: 8080)"
    echo "  SERVE_PORT               Container port for 'serve'/'web' verbs (default: 4096)"
    echo "                           A free host port is auto-selected starting from this value"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Start OpenCode"
    echo "  $0 serve                              # Start headless server (auto port-mapped)"
    echo "  $0 web                                # Start web interface (auto port-mapped)"
    echo "  SERVE_PORT=8888 $0 serve              # Use port 8888"
    echo "  $0 enter                              # Enter a container"
    echo "  $0 logs -f --tail 50                  # Follow logs with last 50 lines"
    echo "  $0 stop                               # Stop a container"
    echo "  DOCKER_ENV='AWS_PROFILE' $0           # Pass AWS_PROFILE to container"
    exit 0
}

# Show help for the wrapper itself (use 'help' verb; --help/-h are forwarded to opencode)
if [ "${1:-}" = "help" ]; then
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

# Detect ACP mode - must come before docker args are built
IS_ACP_MODE=false
if [ "${1:-}" = "acp" ]; then
    IS_ACP_MODE=true
    # ACP uses JSON-RPC over stdio: save real stdout on fd3, then redirect
    # all script output to stderr so nothing corrupts the JSON stream.
    exec 3>&1 1>&2
fi

# Detect serve/web mode - opencode binds to 127.0.0.1 by default which is
# unreachable from outside the container. We need to:
#   1. Override --hostname to 0.0.0.0 so it binds on all interfaces
#   2. Pick a fixed port (so we can map it with -p) and inject --port
#   3. Add the -p HOST_PORT:CONTAINER_PORT mapping to docker args
IS_SERVE_MODE=false
SERVE_VERB=""
for arg in "$@"; do
    if [ "$arg" = "serve" ] || [ "$arg" = "web" ]; then
        IS_SERVE_MODE=true
        SERVE_VERB="$arg"
        break
    fi
done

SERVE_PORT=""
HOST_SERVE_PORT=""
if [ "$IS_SERVE_MODE" = true ]; then
    # Allow overriding via env; default container port is 4096
    SERVE_PORT="${SERVE_PORT:-4096}"
    # Find an available host port starting from the same value
    HOST_SERVE_PORT=$(find_available_port "$SERVE_PORT")
    if [ -z "$HOST_SERVE_PORT" ]; then
        echo -e "${RED}✗ Could not find an available host port for opencode serve${NC}"
        exit 1
    fi
    export SERVE_PORT HOST_SERVE_PORT
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

# Watchdog: restart clipboard bridge if it dies mid-session
WATCHDOG_PID=""
(
    while kill -0 $$ 2>/dev/null; do
        sleep 10
        if ! "$SCRIPT_DIR/lib/manage-clipboard-bridge.sh" status >/dev/null 2>&1; then
            echo -e "${YELLOW}[watchdog] Clipboard bridge died, restarting...${NC}" >&2
            "$SCRIPT_DIR/lib/manage-clipboard-bridge.sh" start >/dev/null 2>&1 || true
        fi
    done
) &
WATCHDOG_PID=$!
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
        TRANSLATION_LOG=$(mktemp /tmp/config-translation-XXXXXX.log)
        python3 "$SCRIPT_DIR/lib/detect-remote-mcps.py" \
            --config "$HOME/.config/opencode/opencode.jsonc" \
            --output "$HOME/.cache/mcp-proxy-config.json" \
            --docker-config "$TEMP_CONFIG_FILE" \
            --port "$PROXY_PORT" \
            --docker \
            2>&1 | tee "$TRANSLATION_LOG"
        TRANSLATION_EXIT=${PIPESTATUS[0]}

        if [ "$TRANSLATION_EXIT" -ne 0 ] || [ ! -f "$TEMP_CONFIG_FILE" ]; then
            echo -e "${RED}✗ Config translation failed (exit code: $TRANSLATION_EXIT)!${NC}"
            if [ ! -f "$TEMP_CONFIG_FILE" ]; then
                echo -e "${RED}  Output config was not created: $TEMP_CONFIG_FILE${NC}"
            fi
            echo ""
            echo "Full output logged to: $TRANSLATION_LOG"
            echo "Cannot start OpenCode with broken config translation."
            rm -rf "$TEMP_CONFIG_DIR"
            exit 1
        fi
        rm -f "$TRANSLATION_LOG"

        echo -e "${GREEN}✓ Config validated and translated for Docker${NC}"

        # Restart mcp-proxy only if the config changed, to pick up new servers or
         # --allow-http flags. Uses mkdir-based locking (atomic on macOS, unlike flock).
         PROXY_CONFIG_CHECKSUM_FILE="$HOME/.cache/mcp-proxy-config.checksum"
         PROXY_RESTART_LOCK="$HOME/.cache/mcp-proxy-restart.lock.d"
         NEW_CHECKSUM=$(md5 -q "$HOME/.cache/mcp-proxy-config.json" 2>/dev/null || md5sum "$HOME/.cache/mcp-proxy-config.json" 2>/dev/null | awk '{print $1}')

         if mkdir "$PROXY_RESTART_LOCK" 2>/dev/null; then
             trap "rmdir '$PROXY_RESTART_LOCK' 2>/dev/null" EXIT
             OLD_CHECKSUM=$(cat "$PROXY_CONFIG_CHECKSUM_FILE" 2>/dev/null || echo "")
             if [ "$NEW_CHECKSUM" != "$OLD_CHECKSUM" ]; then
                 echo "mcp-proxy config changed — restarting to pick up new config..."
                 if "$SCRIPT_DIR/manage-mcp-proxy.sh" restart >/dev/null 2>&1; then
                     echo "$NEW_CHECKSUM" > "$PROXY_CONFIG_CHECKSUM_FILE"
                     echo -e "${GREEN}✓ mcp-proxy restarted with updated config${NC}"
                 else
                     echo -e "${YELLOW}⚠ mcp-proxy restart failed — check logs: $HOME/.cache/mcp-proxy.log${NC}"
                 fi
             else
                 echo -e "${GREEN}✓ mcp-proxy config unchanged, no restart needed${NC}"
             fi
             rmdir "$PROXY_RESTART_LOCK" 2>/dev/null
         else
             echo -e "${GREEN}✓ mcp-proxy config update handled by another instance${NC}"
         fi
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
        # Safety: only delete if path is under a known temp root (macOS or Linux)
        case "$TEMP_CONFIG_DIR" in
            /var/folders/*|/tmp/*)
                # Some subdirs (memory/, journal/) are direct host mounts and may be
                # root-owned inside the temp dir — rm -rf will fail on them. That's fine:
                # temp dirs are cleared on reboot so any leftover empty dirs are harmless.
                rm -rf "$TEMP_CONFIG_DIR" 2>/dev/null || true
                ;;
            *)
                echo -e "${YELLOW}⚠ Skipping cleanup of unexpected temp dir: $TEMP_CONFIG_DIR${NC}"
                ;;
        esac
    fi
}

cleanup_all() {
    echo ""
    echo "Cleaning up..."
    cleanup_bridge
    cleanup_git_credential_proxy
    cleanup_config
    [ -n "${WATCHDOG_PID:-}" ] && kill "$WATCHDOG_PID" 2>/dev/null || true
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}

trap cleanup_all EXIT INT TERM

# Ensure persistent memory/journal dirs exist on the host before mounting
mkdir -p "$HOME/.config/opencode/memory" "$HOME/.config/opencode/journal"

# Step 5: Build docker command
echo "Starting OpenCode in Docker..."
echo -e "  Image: ${GREEN}$IMAGE${NC}"
echo -e "  OAuth proxy: ${GREEN}host.docker.internal:$PROXY_PORT${NC}"
if [ "$CLIPBOARD_READY" = true ]; then
    echo -e "  Clipboard: ${GREEN}macOS → container (shared)${NC}"
fi
if [ "$IS_SERVE_MODE" = true ]; then
    echo -e "  Serve mode: ${GREEN}$SERVE_VERB → http://localhost:$HOST_SERVE_PORT${NC}"
fi
echo ""

# No need to clean up - random suffix prevents collisions

DOCKER_ARGS=(
    $([ "$IS_ACP_MODE" = true ] && echo "-i" || echo "-it")
    --rm
    -v "$HOME/.cache/opencode:/root/.cache/opencode"
    -v "$HOME/.local/state/opencode/$PROJECT_NAME:/root/.local/state/opencode"
    -v "$HOME/.local/share/opencode:/root/.local/share/opencode"
    -v "$HOME/.cache/opencode-docker/:/root/.cache"
    # Named volume for Playwright browsers — Docker auto-seeds from image on first use,
    # so browsers are available immediately without a separate install step.
    # Survives container restarts; delete with: docker volume rm opencode-ms-playwright
    -v "opencode-ms-playwright:/root/.cache/ms-playwright"
    # -v "$HOME/.gitconfig:/root/.gitconfig"
    -v "$TEMP_CONFIG_DIR:/root/.config/opencode"
    -v "$HOME/.config/opencode:/root/.config/opencode-host:ro"
    # Persist agent memory and journal through the temp config overlay
    -v "$HOME/.config/opencode/memory:/root/.config/opencode/memory"
    -v "$HOME/.config/opencode/journal:/root/.config/opencode/journal"
    -v "$PWD:$PWD"
    -w "${PWD:-/root}"
    --name "$CONTAINER_NAME"
    # Persistent Python virtual environments (avoids host/container .venv conflicts)
    # -v "$VENV_CACHE_DIR/poetry:/root/.cache/pypoetry/virtualenvs"
    # -v "$VENV_CACHE_DIR/uv:/root/.cache/uv/venvs"
)

# Expose serve/web port when needed
if [ "$IS_SERVE_MODE" = true ]; then
    DOCKER_ARGS+=(-p "${HOST_SERVE_PORT}:${SERVE_PORT}")
fi

# Generate unique container ID from container name (to avoid conflicts when sharing /tmp)
# Extract numeric suffix from container name (e.g., "opencode-myproject-12345" -> "12345")
CONTAINER_ID=$(echo "$CONTAINER_NAME" | grep -o '[0-9]*$' || echo "$$")
DOCKER_ARGS+=(-e "CONTAINER_ID=$CONTAINER_ID")

# Pass host HOME so container can create a symlink and translate paths
DOCKER_ARGS+=(-e "HOST_HOME=$HOME")

# Pass the host-side state dir so editor-bridge can translate /root/.local/state/opencode
# to the correct host path (which is project-namespaced: ~/.local/state/opencode/<project>)
DOCKER_ARGS+=(-e "HOST_STATE_DIR=$HOME/.local/state/opencode/$PROJECT_NAME")

# Set DISPLAY: forward to XQuartz if running, otherwise use virtual framebuffer.
# XQuartz creates /tmp/.X11-unix/X0 when active; that's the most reliable indicator.
if [ -S /tmp/.X11-unix/X0 ] || pgrep -x "X11.bin" > /dev/null 2>&1 || pgrep -x "quartz-wm" > /dev/null 2>&1; then
    DOCKER_ARGS+=(-e "DISPLAY=host.docker.internal:0")
    echo -e "  Display: ${GREEN}XQuartz detected → forwarding X11 (headed browser supported)${NC}"
else
    # Fake DISPLAY for clipboard tools (will be overridden by entrypoint to unique value)
    DOCKER_ARGS+=(-e "DISPLAY=:99")
fi

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

echo -e "  Real config (ro): ${GREEN}$HOME/.config/opencode → /root/.config/opencode-host${NC}"

# Add optional user-specific mounts if environment variables are set
if [ -n "$OPENCODE_CONFIG_DIR" ]; then
    DOCKER_ARGS+=(-v "$OPENCODE_CONFIG_DIR:/root/.config/opencode")
    echo -e "  Config override: ${GREEN}$OPENCODE_CONFIG_DIR${NC}"
fi

# Mount real (untranslated) opencode config read-write at the host path so it
# can be edited from inside the container. Opencode itself still uses the
# translated config at /root/.config/opencode; this mount lands at
# $HOST_HOME/.config/opencode (e.g. /Users/jan.kirsten/.config/opencode) which
# is a different path from /root/.config/opencode inside the container.
if [ "${MOUNT_OPENCODE_CONFIG:-0}" = "1" ]; then
    DOCKER_ARGS+=(-v "$HOME/.config/opencode:$HOME/.config/opencode")
    echo -e "  Real config (rw): ${GREEN}$HOME/.config/opencode${NC}"
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

# Add clipboard bridge volumes:
#   /shared     (read-only)  host → container: paste from macOS clipboard
#   /shared-out (read-write) container → host: copy to macOS clipboard
CLIPBOARD_OUT_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/opencode/clipboard-out"
mkdir -p "$CLIPBOARD_OUT_DIR"
DOCKER_ARGS+=(
    -v "${CLIPBOARD_DIR}:/shared:ro"
    -v "${CLIPBOARD_OUT_DIR}:/shared-out"
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

# Build final opencode args, injecting serve flags when needed.
# opencode serve/web defaults to --hostname 127.0.0.1 (loopback only), which is
# unreachable from outside the container. Force 0.0.0.0 and a fixed port so the
# -p mapping we added to DOCKER_ARGS above actually works.
OPENCODE_ARGS=()
if [ $# -gt 0 ]; then
    OPENCODE_ARGS=("$@")
fi
if [ "$IS_SERVE_MODE" = true ]; then
    # Only inject if the user hasn't already supplied these flags
    if ! printf '%s\n' "${OPENCODE_ARGS[@]}" | grep -q -- '--hostname'; then
        OPENCODE_ARGS+=(--hostname 0.0.0.0)
    fi
    if ! printf '%s\n' "${OPENCODE_ARGS[@]}" | grep -q -- '--port'; then
        OPENCODE_ARGS+=(--port "$SERVE_PORT")
    fi
    echo -e "${GREEN}  → Connect at: http://localhost:${HOST_SERVE_PORT}${NC}"
    echo ""
fi

if [ "$IS_ACP_MODE" = true ]; then
    # ACP mode: opencode acp speaks JSON-RPC over stdio.
    # All startup noise must go to stderr so it doesn't corrupt the JSON stream.
    # Run opencode directly (no TTY entrypoint) with stdin kept open (-i).
    exec docker run "${DOCKER_ARGS[@]}" "$IMAGE" opencode ${OPENCODE_ARGS[@]+"${OPENCODE_ARGS[@]}"} 1>&3 2>/dev/null
else
    echo -e "${YELLOW}Note: If you authenticate CLI tools (gh, etc.) after starting,${NC}"
    echo -e "${YELLOW}      you'll need to restart the container to use them.${NC}"
    echo ""

    # Run docker with TTY-preserving entrypoint
    echo "[Host] Executing docker run command..."
    docker run "${DOCKER_ARGS[@]}" "$IMAGE" opencode-entrypoint-tty ${OPENCODE_ARGS[@]+"${OPENCODE_ARGS[@]}"}
fi

# Cleanup happens automatically via trap
