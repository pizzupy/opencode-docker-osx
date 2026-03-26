# opencode-docker

Run [opencode](https://opencode.ai) inside a Docker container for isolation, while keeping host integration working:

- **URL/file opening** — `open`/`xdg-open` calls from the container open on the host (browser, Finder, etc.)
- **Clipboard paste** — macOS clipboard (text and images) is available inside the container via Ctrl+V
- **Clipboard copy** — container processes can write to the macOS clipboard via `xclip`/`xsel`
- **MCP servers** — remote MCP servers (OAuth-based) work via `mcp-proxy` on the host
- **SSH agent** — forwarded from Docker Desktop's built-in SSH agent
- **Git credentials** — optional proxy to macOS Keychain

Not meant to be a hardened security boundary — just enough isolation so you don't feel the need to watch over the LLM's shoulder all the time. The TUI runs inside Docker (no client/server split). Easy to update and customize.

## Quick Start

```bash
# First time: build both layers
./build-all.sh

# Run opencode in the current directory
./run-opencode.sh

# Update opencode to latest version (fast, only rebuilds the opencode layer)
./update-opencode.sh
```

## Build System

Two-layer build for fast iteration:

| Image | Contents | When to rebuild |
|-------|----------|-----------------|
| `opencode-base` | Ubuntu + dev tools (rg, fd, bat, node, python, etc.) | Rarely (quarterly) |
| `opencode-dev` | opencode + bridge integrations | On opencode updates |

```bash
./build-base.sh       # Build base layer (~2.5 GB, slow)
./build-opencode.sh   # Build opencode layer (~100 MB on top, fast)
./build-all.sh        # Build both

./update-opencode.sh          # Check for updates and rebuild if needed
./update-opencode.sh --force  # Force rebuild
./update-opencode.sh --check  # Check only, don't build
```

## Running

```bash
./run-opencode.sh               # Start opencode in current directory
./run-opencode.sh enter         # Enter a running container (bash)
./run-opencode.sh logs -f       # Follow container logs
./run-opencode.sh stop          # Stop a running container
./run-opencode.sh ps            # List running containers

# Pass environment variables to the container
DOCKER_ENV="AWS_PROFILE,MY_TOKEN=abc" ./run-opencode.sh
```

## How It Works

### URL & File Opening

`run-opencode.sh` starts `lib/host-url-opener.py` — a small HTTP server on the host (random port, token-authenticated). It writes connection details to a temp dir shared as a read-only volume.

Inside the container, `open` and `xdg-open` are replaced by `lib/container-open-wrapper.sh`, which:
- Translates bare file paths to `file://` URLs
- Translates `/root/...` paths to the host home path (`$HOST_HOME`)
- POSTs to the host HTTP service

Node packages that bundle their own `xdg-open` (playwright, `open` package, etc.) are patched at container startup by `lib/patch-npm-open.sh`.

### Clipboard

`lib/clipboard-sync.sh` runs on the host, polling the macOS clipboard every 300ms. It writes to `~/.cache/opencode/clipboard-bridge/`:
- `clipboard.mime` — content type (`text/plain` or `image/png`)
- `clipboard.txt` — text content
- `clipboard.b64` — base64-encoded PNG for images

This directory is mounted read-only into the container at `/shared`. `lib/xclip-wrapper.sh` and `lib/xsel-wrapper.sh` replace the real `xclip`/`xsel` and serve reads from `/shared`.

For **container → host** copy, wrappers write to `/shared-out` (mounted read-write). `clipboard-sync.sh` picks this up and calls `pbcopy`.

The clipboard bridge is auto-restarted by a watchdog loop in `run-opencode.sh` if it dies.

### $HOME Path

Inside the container `$HOME=/root`, but the host home is e.g. `/Users/jan`. The entrypoint creates a symlink `$HOST_HOME → /root` so paths like `/Users/jan/.local/state/opencode/...` resolve correctly inside the container, and the open wrapper can translate them back for the host.

### MCP Proxy

`lib/detect-remote-mcps.py` reads `~/.config/opencode/opencode.jsonc`, detects remote MCP servers (using `mcp-remote`), and rewrites the config to point to `mcp-proxy` running on the host at `host.docker.internal:PORT`. `manage-mcp-proxy.sh` manages the `mcp-proxy` daemon.

## Configuration

The host's `~/.config/opencode/` is copied into the container (with MCP config translated). Other opencode state dirs are mounted directly:

| Host | Container |
|------|-----------|
| `~/.config/opencode/` | `/root/.config/opencode/` (translated copy) |
| `~/.cache/opencode/` | `/root/.cache/opencode/` |
| `~/.local/state/opencode/` | `/root/.local/state/opencode/` |
| `~/.local/share/opencode/` | `/root/.local/share/opencode/` |
| `$PWD` | `$PWD` (same path) |

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGE` | `opencode-dev:latest` | Docker image to use |
| `PROXY_PORT` | `8080` | Port for mcp-proxy |
| `DOCKER_ENV` | — | Extra env vars to pass through (comma-separated) |
| `EXTRA_MOUNTS` | — | Extra volume mounts (comma-separated `host:container`) |
| `ENABLE_GIT_CREDENTIAL_PROXY` | `false` | Enable macOS Keychain git credential proxy |
