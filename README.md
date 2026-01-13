# OpenCode Docker with good ergonomy for OSX hosts

Docker environment for OpenCode with automatic OAuth support, Ctrl-V for image pasting, host configurations reuse and other ergonomics. This is not meant to produce an image that is hosted publically, it's meant to generate a local image based on your needs, to provide reasonable isolation from the LLM. It's not meant to be hardened against a targeted attack or anything like that, and instead, is meant to provide some isolation so that you don't feel the need to look over the LLM shoulder all the time. The Opencode project already provides a simple Docker image. This one is meant to be ergonomic for daily use and easy to update/customize.

## Quick Start

```bash
# 1. Build the image
make build

# 2. Setup OAuth for remote MCPs (one-time)
./setup-mcp-proxy-auto.sh

# 3. Run OpenCode
./run-opencode.sh
```

## Daily usage

``` bash
❯ ## update or make build

❯ cat ~/.local/bin/opencode-docker 
#!/usr/bin/env zsh

DOCKER_HOME=/root
export EXTRA_MOUNTS="$HOME/.keys:$DOCKER_HOME/.keys:ro,$HOME/code:$HOME/code"
$HOME/code/.../run-opencode.sh

❯ opencode-docker
TUI...
```

## What's Included

The baseline is Ubuntu.

**Core Tools:** OpenCode, uv, Node.js, npm, ripgrep, fd, bat, eza, delta, jq, yq, gh  
**Shells:** bash, zsh (oh-my-zsh), fish  
**Graphing:** Mermaid, Graphviz, PlantUML, D2  
**Development:** pyright, ruff, black, mypy, ast-grep, semgrep, shellcheck

## Magic Features

This setup includes several ergonomic enhancements to make Docker feel like native development:

### 🎯 Smart Container Naming
Containers are named after the project folder with a random suffix (allows multiple instances):
```bash
cd ~/projects/myapp
./run-opencode.sh  # Creates container: opencode-myapp-12345
./run-opencode.sh  # Can run again: opencode-myapp-67890
```

### 🚪 Enter Running Containers
Jump into a running container's shell for maintenance:
```bash
./run-opencode.sh enter  # Opens bash in the most recent container for current project
```
This gives you the exact same environment OpenCode is running in. If multiple containers are running for the same project, it enters the first one found.

### 📋 Clipboard Integration
macOS clipboard automatically syncs to all containers:
- Copy on Mac → Paste in OpenCode (Ctrl+V)
- Supports both text and images
- **Shared daemon:** One background process serves all OpenCode instances
- Persistent location: `~/.cache/opencode/clipboard-bridge`
- Manage manually: `./lib/manage-clipboard-bridge.sh {start|stop|status|restart}`

### 🔐 SSH Agent Forwarding
Your SSH keys work seamlessly in the container:
- Automatic SSH agent socket forwarding
- Git operations use your host SSH keys
- No need to copy keys into container

### 🔑 Git Credential Proxy (Optional)
Access macOS Keychain credentials from inside the container:
- Enable with: `ENABLE_GIT_CREDENTIAL_PROXY=true ./run-opencode.sh`
- Git operations automatically use stored credentials
- Works with GitHub, GitLab, Bitbucket, etc.
- No need to re-enter passwords or tokens
- See [GIT-CREDENTIAL-PROXY.md](GIT-CREDENTIAL-PROXY.md) for details

### 🐍 Poetry/uv Virtual Environment Isolation
Python virtual environments are stored outside project directories:
- **Host (macOS):** Uses `.venv` in project folder
- **Container:** Uses `~/.cache/opencode/docker-venvs/`
- Prevents platform-incompatible `.venv` conflicts
- Poetry configured with `virtualenvs.in-project=false`

### 🔄 Auto-Update Script
Automatically checks for OpenCode updates and rebuilds:
```bash
./update-opencode.sh           # Check and update if needed
./update-opencode.sh --force   # Force rebuild
./update-opencode.sh --check   # Only check version
```

### 🌐 OAuth Flow Magic
Complex OAuth handling for both MCPs and CLI tools:

**For MCP Servers (Linear, Notion, etc.):**
- mcp-proxy runs on Mac host
- Handles OAuth callbacks on localhost
- Browser opens natively on Mac
- Transparent to OpenCode in container

**For CLI Tools (gh, npm, etc.):**
- URL bridge intercepts `open` commands
- Forwards URLs to Mac's default browser
- Works with any tool that tries to open URLs

### 🔧 Extra Mount Support
Pass additional Docker volumes via environment variables:
```bash
# Single mount
EXTRA_MOUNTS="$HOME/data:/data" ./run-opencode.sh

# Multiple mounts (comma-separated)
EXTRA_MOUNTS="$HOME/data:/data,$HOME/configs:/configs:ro" ./run-opencode.sh

# Override entire config directory
OPENCODE_CONFIG_DIR="$HOME/custom-config" ./run-opencode.sh
```

### 🎨 Complete Ecosystem
Pre-installed development tools:
- **Modern CLI:** ripgrep, fd, bat, eza, delta
- **Python:** uv, poetry, pyright, ruff, black, mypy
- **Node.js:** Latest LTS with npm/npx
- **Git tools:** gh (GitHub CLI), delta (better diffs)
- **Shells:** bash, zsh (oh-my-zsh), fish
- **Graphing:** Mermaid, Graphviz, PlantUML, D2
- **Code analysis:** ast-grep, semgrep, shellcheck  

## OAuth Support

### How It Works

```
┌─── Mac Host ─────────────────────────────────┐
│  mcp-proxy :8080                             │
│    Proxies to remote OAuth MCPs              │
│    Handles OAuth callbacks                   │
└───────────────────────────────────────────────┘
         ↑ via host.docker.internal:8080
┌─── Docker Container ──────────────────────────┐
│  OpenCode                                     │
│    Uses ~/.config/opencode-docker/           │
│    Connects to mcp-proxy endpoints           │
└───────────────────────────────────────────────┘
```

**Key Points:**
- mcp-proxy runs on Mac host (handles OAuth callbacks)
- Docker connects via `host.docker.internal:8080`
- Browser opens natively on Mac for OAuth
- Original config at `~/.config/opencode/` never modified
- Docker uses separate config at `~/.config/opencode-docker/`

## Usage

### Basic

```bash
./run-opencode.sh              # Run OpenCode with OAuth
./run-opencode.sh enter        # Enter running container's bash shell
./manage-mcp-proxy.sh status   # Check mcp-proxy status
./manage-mcp-proxy.sh logs     # View logs
./debug.sh                     # Quick diagnostics
./update-opencode.sh           # Check for updates and rebuild
```

### Makefile Targets

```bash
make build         # Build Docker image
make update        # Update OpenCode
make shell         # Interactive bash
make zsh           # Interactive zsh
make fish          # Interactive fish
```

### Environment Variables

Control optional features and behavior:

```bash
# Enable git credential proxy for macOS Keychain access
ENABLE_GIT_CREDENTIAL_PROXY=true ./run-opencode.sh

# Change MCP proxy port (default: 8080)
PROXY_PORT=9090 ./run-opencode.sh

# Add extra volume mounts
EXTRA_MOUNTS="$HOME/data:/data,$HOME/configs:/configs:ro" ./run-opencode.sh

# Override config directory
OPENCODE_CONFIG_DIR="$HOME/custom-config" ./run-opencode.sh

# Use custom Docker image
IMAGE=my-custom-opencode:latest ./run-opencode.sh
```

To make settings permanent, add to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.):

```bash
export ENABLE_GIT_CREDENTIAL_PROXY=true
export PROXY_PORT=8080
```

## Troubleshooting

### OAuth Not Working

```bash
./manage-mcp-proxy.sh status   # Check if running
./manage-mcp-proxy.sh logs     # View logs
./manage-mcp-proxy.sh restart  # Restart
```

### No Remote MCPs Detected

```bash
python3 detect-remote-mcps.py --dry-run
```

Ensure your config has commands containing `mcp-remote` with URLs.

### Config Errors

```bash
./setup-mcp-proxy-auto.sh  # Regenerate configs
```

### Clipboard Not Working

```bash
./lib/manage-clipboard-bridge.sh status   # Check if running
./lib/manage-clipboard-bridge.sh restart  # Restart daemon
```

Common issues:
- **Empty clipboard on start:** The daemon only syncs when clipboard changes. Copy something to trigger sync.
- **Stale PID file:** Run `./lib/manage-clipboard-bridge.sh stop` to clean up.
- **Multiple instances:** All containers share one daemon automatically.

### Debug

```bash
./debug.sh  # Shows status, configs, connectivity
```

## Architecture

### Two-Component System

The environment uses two distinct services to handle different types of host interactions:

1.  **mcp-proxy (for MCPs)**
    *   **Purpose:** Runs MCP servers (like Linear) directly on the host.
    *   **Why:** These servers need to receive OAuth callbacks on specific localhost ports.
    *   **Flow:** Docker -> `host.docker.internal:8080` -> mcp-proxy (Host) -> Actual MCP Server (Host)

2.  **URL Bridge (for CLI Tools)**
    *   **Purpose:** Allows generic CLI tools (e.g., `gh auth login`, `npm login`) to open the host browser.
    *   **Why:** These tools just try to run `open` or `xdg-open`. The bridge intercepts this and forwards the URL to the host.
    *   **Flow:** CLI Tool -> `open` (shim) -> URL Bridge (Host) -> Default Browser

### OAuth Flow (MCPs)

1. OpenCode (Docker) requests data from Linear
2. Connects to `host.docker.internal:8080/servers/linear/sse`
3. mcp-proxy (Mac) runs `npx mcp-remote https://mcp.linear.app/mcp`
4. OAuth required → browser opens on Mac
5. User authorizes
6. Callback goes to localhost on Mac (mcp-proxy handles it)
7. OAuth complete → request succeeds

### Configuration

**Original (unchanged):**
```json
{
  "linear": {
    "command": ["npx", "-y", "mcp-remote", "https://mcp.linear.app/mcp"]
  }
}
```

**Docker (auto-generated):**
```json
{
  "linear": {
    "type": "remote",
    "url": "http://host.docker.internal:8080/servers/linear/sse"
  }
}
```

**mcp-proxy (auto-generated):**
```json
{
  "mcpServers": {
    "linear": {
      "command": "npx -y mcp-remote https://mcp.linear.app/mcp"
    }
  }
}
```

### File Structure

```
~/.config/
├── opencode/              # Original (unchanged)
│   └── opencode.jsonc
└── opencode-docker/       # Docker-specific (auto-generated)
    └── opencode.jsonc

~/.cache/
├── mcp-proxy-config.json  # Generated proxy config
└── mcp-proxy.log          # Proxy logs
```

## Files

```
run-opencode.sh (or opencode-docker)  # Run OpenCode with OAuth
setup-mcp-proxy-auto.sh               # One-time OAuth setup
manage-mcp-proxy.sh                   # Manage mcp-proxy service
debug.sh                              # Quick diagnostics
update-opencode.sh                    # Update OpenCode version
lib/                                  # Support scripts (auto-used)
```

## Advanced

### Custom Port

```bash
PROXY_PORT=8081 ./setup-mcp-proxy-auto.sh
```

### Native OpenCode (not Docker)

```bash
python3 detect-remote-mcps.py --native
```

Uses `localhost` instead of `host.docker.internal`.

## Notes

- Original config never modified
- Docker uses separate config directory
- mcp-proxy runs as background service on Mac
- OAuth callbacks handled on Mac host
- Works with unlimited OAuth-based remote MCPs

## Quick Reference

### Common Commands
```bash
# Start OpenCode
./run-opencode.sh

# Enter running container
./run-opencode.sh enter

# Update OpenCode
./update-opencode.sh

# Manage mcp-proxy
./manage-mcp-proxy.sh status|start|stop|restart|logs

# Diagnostics
./debug.sh
```

### Environment Variables
```bash
# Custom proxy port
PROXY_PORT=8081 ./run-opencode.sh

# Extra Docker mounts
EXTRA_MOUNTS="$HOME/data:/data" ./run-opencode.sh

# Override config directory
OPENCODE_CONFIG_DIR="$HOME/custom-config" ./run-opencode.sh

# Pass GitHub token
GH_TOKEN=ghp_xxx ./run-opencode.sh
```

### Container Naming
Containers are automatically named: `opencode-{folder-name}-{random}`
- `~/projects/myapp` → `opencode-myapp-12345`
- `~/work/api-server` → `opencode-api-server-67890`
- Multiple instances per folder are supported with different random suffixes

### File Locations
```
~/.config/opencode/              # Original config (unchanged)
~/.config/opencode-docker/       # Docker config (auto-generated)
~/.cache/opencode/docker-venvs/  # Python venvs (isolated)
~/.cache/mcp-proxy-config.json   # Proxy config
~/.cache/mcp-proxy.log           # Proxy logs
```

## License

Provided as-is for development purposes.
