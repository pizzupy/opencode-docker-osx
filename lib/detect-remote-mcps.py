#!/usr/bin/env python3
"""
detect-remote-mcps.py - Automatically detect and configure remote MCP servers

This script:
1. Parses the user's opencode.jsonc config
2. Detects remote MCP servers (using mcp-remote)
3. Generates mcp-proxy config for all remote servers
4. Updates opencode.jsonc to use mcp-proxy endpoints
"""

import json
import re
import sys
import os
from pathlib import Path
from typing import Dict, List, Tuple, Any


def resolve_file_refs(value: str) -> str:
    """Resolve {file:path} references — e.g. {file:~/.keys/github-ro} → token content."""
    def replacer(m):
        path = os.path.expanduser(m.group(1))
        try:
            with open(path) as f:
                return f.read().strip()
        except (OSError, IOError):
            return m.group(0)
    return re.sub(r'\{file:([^}]+)\}', replacer, value)

def strip_jsonc_comments(content: str) -> str:
    """Remove comments and trailing commas from JSONC to make it valid JSON."""
    result = []
    in_string = False
    in_single_line_comment = False
    in_multi_line_comment = False
    escape_next = False
    
    i = 0
    while i < len(content):
        char = content[i]
        next_char = content[i + 1] if i + 1 < len(content) else None
        
        # Handle escape sequences in strings
        if in_string and escape_next:
            result.append(char)
            escape_next = False
            i += 1
            continue
        
        if in_string and char == '\\':
            result.append(char)
            escape_next = True
            i += 1
            continue
        
        # Handle string boundaries
        if char == '"' and not in_single_line_comment and not in_multi_line_comment:
            in_string = not in_string
            result.append(char)
            i += 1
            continue
        
        # If we're in a string, just copy the character
        if in_string:
            result.append(char)
            i += 1
            continue
        
        # Handle multi-line comment end
        if in_multi_line_comment:
            if char == '*' and next_char == '/':
                in_multi_line_comment = False
                i += 2
                continue
            i += 1
            continue
        
        # Handle single-line comment end
        if in_single_line_comment:
            if char == '\n':
                in_single_line_comment = False
                result.append(char)
            i += 1
            continue
        
        # Check for comment starts
        if char == '/' and next_char == '/':
            in_single_line_comment = True
            i += 2
            continue
        
        if char == '/' and next_char == '*':
            in_multi_line_comment = True
            i += 2
            continue
        
        # Copy non-comment content
        result.append(char)
        i += 1
    
    # Join and remove trailing commas
    content = ''.join(result)
    content = re.sub(r',(\s*[}\]])', r'\1', content)
    
    return content

def parse_jsonc(file_path: str) -> Dict:
    """Parse a JSONC file (JSON with comments)."""
    with open(file_path, 'r') as f:
        content = f.read()
    
    # Strip comments and trailing commas
    clean_content = strip_jsonc_comments(content)
    
    try:
        return json.loads(clean_content)
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON: {e}", file=sys.stderr)
        print(f"Content around error: {clean_content[max(0, e.pos-50):e.pos+50]}", file=sys.stderr)
        raise

def detect_remote_mcps(config: Dict, always_proxy: set | None = None) -> Dict[str, str]:
    """
    Detect remote MCP servers from config.

    always_proxy: set of server names to include even if enabled:false.
    These are routed through mcp-proxy so their SSE endpoints exist at startup;
    opencode's enabled flag still controls whether it actually connects.

    Returns a dict mapping server name to remote URL.
    """
    remote_mcps = {}
    
    # Try both 'mcp' and 'mcpServers' keys (different OpenCode versions)
    mcp_servers = config.get('mcp', config.get('mcpServers', {}))
    
    for name, server_config in mcp_servers.items():
        if not isinstance(server_config, dict):
            continue
        
        # Skip disabled servers — mcp-proxy 0.11.0 eagerly connects to all named
        # servers at startup, so including a disabled/unreachable server crashes
        # the whole proxy. Exception: servers in always_proxy are routed through
        # mcp-proxy regardless, so opencode can connect after enabling in the UI
        # (needed for streamable-HTTP servers that opencode can't speak natively).
        if server_config.get('enabled') is False:
            if not always_proxy or name not in always_proxy:
                continue

        command = server_config.get('command', [])
        args = server_config.get('args', [])
        
        # Convert to list if string
        if isinstance(command, str):
            command = [command]
        if isinstance(args, str):
            args = [args]
        
        # Check if this is a remote MCP using mcp-remote
        is_remote = False
        remote_url = None

        # Pattern 0: native type: "remote" with a url field (opencode native format)
        if server_config.get('type') == 'remote' and 'url' in server_config:
            remote_url = server_config['url']
            is_remote = True
            # Skip URLs that are already mcp-proxy SSE endpoints (e.g. from a
            # previous translation run or a manually configured local proxy).
            # mcp-proxy SSE endpoints follow the pattern /servers/<name>/sse.
            if re.search(r'/servers/[^/]+/sse$', remote_url):
                is_remote = False
                remote_url = None

        # Pattern 1: ["npx", "-y", "mcp-remote", "https://..."]
        if len(command) >= 3 and command[0] == "npx" and "mcp-remote" in command:
            # URL might be in command or args
            for item in command + args:
                if isinstance(item, str) and item.startswith('http'):
                    remote_url = item
                    is_remote = True
                    break
        
        # Pattern 2: ["mcp-remote", "https://..."]
        elif len(command) >= 1 and command[0] == "mcp-remote":
            for item in command[1:] + args:
                if isinstance(item, str) and item.startswith('http'):
                    remote_url = item
                    is_remote = True
                    break
        
        # Pattern 3: command is something else but args contain a URL
        elif args:
            for item in args:
                if isinstance(item, str) and item.startswith('http'):
                    # Check if this looks like a remote MCP URL
                    if 'mcp' in item.lower():
                        remote_url = item
                        is_remote = True
                        break
        
        if is_remote and remote_url:
            remote_mcps[name] = remote_url
    
    return remote_mcps

def detect_host_local_mcps(config: Dict, sidecar_path: str | None = None) -> Dict[str, Dict[str, Any]]:
    """
    Detect local MCP servers listed in the opencode-docker.json sidecar file.

    These are stdio-based servers that must run on the Mac host (e.g. because
    they need a browser/display) rather than inside the Docker container.
    mcp-proxy will launch them as named servers, exposing them as SSE endpoints
    that the container connects to via host.docker.internal.

    Configured via a sidecar file next to opencode.jsonc (opencode never reads it):
        ~/.config/opencode/opencode-docker.json
        { "hostMcpServers": ["playwright"] }

    Returns a dict mapping server name to a structured dict with keys:
        command: str  — the executable
        args: list    — list of individual arguments
        env: dict     — environment variables (may be empty)
    """
    host_local = {}

    if sidecar_path is None:
        sidecar_path = os.path.expanduser('~/.config/opencode/opencode-docker.json')

    if not os.path.exists(sidecar_path):
        return host_local

    try:
        with open(sidecar_path) as f:
            sidecar = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(f"  Warning: could not read sidecar {sidecar_path}: {e}", file=sys.stderr)
        return host_local

    host_server_names = sidecar.get('hostMcpServers', [])
    if not host_server_names:
        return host_local

    mcp_servers = config.get('mcp', config.get('mcpServers', {}))

    for name in host_server_names:
        server_config = mcp_servers.get(name)
        if not isinstance(server_config, dict):
            print(f"  Warning: hostMcpServer '{name}' not found in mcp config, skipping", file=sys.stderr)
            continue

        # Note: we intentionally ignore enabled:false here. mcp-proxy must know about
        # the server at startup to serve its endpoint. The enabled flag in opencode
        # controls whether opencode actually connects — the proxy endpoint always exists.
        command = server_config.get('command', '')
        args = server_config.get('args', [])
        env = server_config.get('environment', server_config.get('env', {}))

        if isinstance(command, list):
            # command was specified as a list — first element is the executable
            cmd_exe = command[0] if command else ''
            extra_args = list(command[1:])
        else:
            cmd_exe = command or ''
            extra_args = []

        if not cmd_exe:
            print(f"  Warning: hostMcpServer '{name}' has no command, skipping", file=sys.stderr)
            continue

        if isinstance(args, list):
            args_list = extra_args + list(args)
        elif isinstance(args, str) and args:
            args_list = extra_args + [args]
        else:
            args_list = extra_args

        host_local[name] = {
            "command": cmd_exe,
            "args": args_list,
            "env": dict(env) if env else {},
        }

    return host_local

def generate_mcp_proxy_config(
    remote_mcps: Dict[str, str],
    host_local_mcps: Dict[str, Dict[str, Any]] | None = None,
    remote_mcp_headers: Dict[str, Dict] | None = None,
) -> Dict:
    """
    Generate mcp-proxy config file format.

    remote_mcp_headers: per-server header dicts (e.g. {Authorization: "Bearer ..."}).
    {file:...} refs are resolved so mcp-remote receives the actual token value and can
    skip OAuth discovery (servers like GitHub Copilot MCP don't support dynamic client
    registration but do accept Bearer tokens).

    mcp-proxy expects a JSON file with 'mcpServers' key containing server definitions.
    Each entry uses command + args + env (structured) rather than a flat shell string.
    """
    servers = {}

    for name, url in remote_mcps.items():
        # mcp-proxy runs on the Mac host, not inside Docker — translate
        # host.docker.internal back to localhost for the proxy config
        host_url = url.replace("host.docker.internal", "localhost")
        args = ["-y", "mcp-remote", host_url]
        # mcp-remote rejects non-HTTPS URLs unless --allow-http is passed
        if not host_url.startswith("https://"):
            args.append("--allow-http")
        if remote_mcp_headers and name in remote_mcp_headers:
            for key, val in remote_mcp_headers[name].items():
                resolved = resolve_file_refs(str(val))
                args += ["--header", f"{key}: {resolved}"]
        servers[name] = {"command": "npx", "args": args}

    for name, server_info in (host_local_mcps or {}).items():
        # Expand ~ in command and args — subprocess_exec doesn't invoke a shell,
        # so tilde expansion must happen here.
        entry: Dict[str, Any] = {
            "command": os.path.expanduser(server_info["command"]),
            "args": [os.path.expanduser(a) for a in server_info["args"]],
        }
        if server_info.get("env"):
            entry["env"] = server_info["env"]
        servers[name] = entry

    return {"mcpServers": servers}

def translate_localhost_urls(config: Dict, use_docker: bool = True) -> Tuple[Dict, int]:
    """
    Translate localhost/127.0.0.1 URLs to host.docker.internal for Docker.
    
    Returns tuple of (updated_config, count_of_translations)
    """
    if not use_docker:
        return config, 0
    
    # Try both 'mcp' and 'mcpServers' keys
    mcp_key = 'mcp' if 'mcp' in config else 'mcpServers'
    mcp_servers = config.get(mcp_key, {})
    
    translations = 0
    
    for name, server_config in mcp_servers.items():
        if not isinstance(server_config, dict):
            continue
        
        # Check if this is a remote type with a URL
        if server_config.get('type') == 'remote' and 'url' in server_config:
            url = server_config['url']
            
            # Replace localhost and 127.0.0.1 with host.docker.internal
            updated_url = url
            updated_url = re.sub(r'://localhost\b', '://host.docker.internal', updated_url)
            updated_url = re.sub(r'://127\.0\.0\.1\b', '://host.docker.internal', updated_url)
            
            if updated_url != url:
                server_config['url'] = updated_url
                translations += 1
                print(f"  Translated {name}: {url} -> {updated_url}")
        
        # Also check in command/args for URLs (e.g., in environment variables)
        # This handles cases where URL is passed as an argument
        for key in ['command', 'args', 'env']:
            if key in server_config:
                value = server_config[key]
                if isinstance(value, str):
                    updated = value.replace('localhost', 'host.docker.internal')
                    updated = updated.replace('127.0.0.1', 'host.docker.internal')
                    if updated != value:
                        server_config[key] = updated
                        translations += 1
                elif isinstance(value, list):
                    for i, item in enumerate(value):
                        if isinstance(item, str):
                            updated = item.replace('localhost', 'host.docker.internal')
                            updated = updated.replace('127.0.0.1', 'host.docker.internal')
                            if updated != item:
                                value[i] = updated
                                translations += 1
                elif isinstance(value, dict):
                    for k, v in value.items():
                        if isinstance(v, str):
                            updated = v.replace('localhost', 'host.docker.internal')
                            updated = updated.replace('127.0.0.1', 'host.docker.internal')
                            if updated != v:
                                value[k] = updated
                                translations += 1
    
    config[mcp_key] = mcp_servers
    return config, translations

def update_opencode_config(
    config: Dict,
    remote_mcps: Dict[str, str],
    proxy_port: int = 8080,
    use_docker: bool = True,
    host_local_mcps: Dict[str, Dict[str, Any]] | None = None,
) -> Dict:
    """
    Update the opencode config to use mcp-proxy endpoints instead of direct connections.
    
    Since mcp-proxy exposes SSE endpoints, we configure them as type: "remote" with a URL.
    Applies to both remote MCPs and host-local MCPs (from opencode-docker.json sidecar).
    """
    # Try both 'mcp' and 'mcpServers' keys
    mcp_key = 'mcp' if 'mcp' in config else 'mcpServers'
    mcp_servers = config.get(mcp_key, {})
    
    host = "host.docker.internal" if use_docker else "localhost"

    proxied = {**remote_mcps, **(host_local_mcps or {})}

    for name in proxied:
        if name in mcp_servers:
            # Preserve the original enabled state
            original_enabled = mcp_servers[name].get('enabled', True)
            
            # Update to use mcp-proxy SSE endpoint
            # Use type: "remote" since mcp-proxy exposes an SSE server
            mcp_servers[name] = {
                "type": "remote",
                "url": f"http://{host}:{proxy_port}/servers/{name}/sse",
                "enabled": original_enabled
            }
    
    config[mcp_key] = mcp_servers

    # Also translate any other localhost references
    if use_docker:
        print("\nTranslating localhost/127.0.0.1 URLs for Docker...")
        config, count = translate_localhost_urls(config, use_docker)
        if count > 0:
            print(f"✓ Translated {count} localhost reference(s)")
        else:
            print("  No additional localhost references found")
    
    return config

def write_jsonc(file_path: str, config: Dict):
    """Write config back as JSONC (with nice formatting)."""
    leading_comments = []
    
    # Read original file to preserve comments at the top (if it exists)
    if os.path.exists(file_path):
        with open(file_path, 'r') as f:
            original = f.read()
        
        # Extract leading comments
        for line in original.split('\n'):
            stripped = line.strip()
            if stripped.startswith('//') or stripped.startswith('/*') or not stripped:
                leading_comments.append(line)
            else:
                break
    
    # Write new config
    with open(file_path, 'w') as f:
        # Write leading comments
        if leading_comments:
            f.write('\n'.join(leading_comments) + '\n')
        
        # Write JSON with nice formatting
        json.dump(config, f, indent=4)
        f.write('\n')

def main():
    import argparse
    import shutil
    
    parser = argparse.ArgumentParser(description='Detect and configure remote MCP servers')
    parser.add_argument('--config', default=os.path.expanduser('~/.config/opencode/opencode.jsonc'),
                        help='Path to source opencode.jsonc config file')
    parser.add_argument('--output', default=os.path.expanduser('~/.cache/mcp-proxy-config.json'),
                        help='Path to output mcp-proxy config file')
    parser.add_argument('--docker-config', default=os.path.expanduser('~/.config/opencode-docker/opencode.jsonc'),
                        help='Path to Docker-specific config file')
    parser.add_argument('--port', type=int, default=8080,
                        help='Port for mcp-proxy server')
    parser.add_argument('--docker', action='store_true', default=True,
                        help='Configure for Docker (use host.docker.internal)')
    parser.add_argument('--native', dest='docker', action='store_false',
                        help='Configure for native (use localhost)')
    parser.add_argument('--dry-run', action='store_true',
                        help='Show what would be done without making changes')
    
    args = parser.parse_args()
    
    # Ensure cache directory exists
    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    
    # Parse config
    print(f"Reading config from: {args.config}")
    config = parse_jsonc(args.config)
    
    # Read sidecar once — used by both always_proxy and host-local detection
    sidecar_path = os.path.join(os.path.dirname(args.config), 'opencode-docker.json')
    always_proxy: set = set()
    if os.path.exists(sidecar_path):
        try:
            with open(sidecar_path) as f:
                _sidecar = json.load(f)
            always_proxy = set(_sidecar.get('remoteProxyAlways', []))
            if always_proxy:
                print(f"\nremoteProxyAlways servers (proxied even when disabled): {sorted(always_proxy)}")
        except (json.JSONDecodeError, OSError) as e:
            print(f"  Warning: could not read sidecar for always_proxy: {e}", file=sys.stderr)

    # Detect remote MCPs
    print("\nDetecting remote MCP servers...")
    remote_mcps = detect_remote_mcps(config, always_proxy)

    # Detect host-local MCPs (opencode-docker.json sidecar)
    print(f"\nDetecting host-local MCP servers (sidecar: {sidecar_path})...")
    host_local_mcps = detect_host_local_mcps(config, sidecar_path)

    if not remote_mcps and not host_local_mcps:
        print("✗ No remote or host-local MCP servers found in config")
        mcp_servers = config.get('mcp', config.get('mcpServers', {}))
        if mcp_servers:
            print(f"  Found {len(mcp_servers)} MCP server(s), but none matched remote or hostOnly patterns:")
            for name, cfg in mcp_servers.items():
                if isinstance(cfg, dict):
                    server_type = cfg.get('type', 'local')
                    cmd = cfg.get('command', cfg.get('url', '(no command/url)'))
                    print(f"    - {name}: type={server_type}, command/url={cmd!r}")
        else:
            print("  No MCP servers defined in config at all (checked 'mcp' and 'mcpServers' keys)")
        print("\nExpected: servers with type='remote', command-based mcp-remote servers, or listed in opencode-docker.json")
        return 1
    
    if remote_mcps:
        print(f"✓ Found {len(remote_mcps)} remote MCP server(s):")
        for name, url in remote_mcps.items():
            print(f"  - {name}: {url}")

    if host_local_mcps:
        print(f"✓ Found {len(host_local_mcps)} host-local MCP server(s):")
        for name, info in host_local_mcps.items():
            print(f"  - {name}: {info['command']} {' '.join(info['args'])}")

    # Extract per-server headers for remote MCPs (used to pass Bearer tokens to mcp-remote)
    mcp_servers_cfg = config.get('mcp', config.get('mcpServers', {}))
    remote_mcp_headers: Dict[str, Dict] = {}
    for name in remote_mcps:
        headers = mcp_servers_cfg.get(name, {}).get('headers', {})
        if headers:
            remote_mcp_headers[name] = headers
            print(f"  Header keys for {name}: {list(headers.keys())}")

    # Generate mcp-proxy config
    print("\nGenerating mcp-proxy configuration...")
    proxy_config = generate_mcp_proxy_config(remote_mcps, host_local_mcps, remote_mcp_headers)
    
    if args.dry_run:
        print("\n=== DRY RUN: mcp-proxy config ===")
        print(json.dumps(proxy_config, indent=2))
    else:
        with open(args.output, 'w') as f:
            json.dump(proxy_config, f, indent=2)
        print(f"✓ Wrote mcp-proxy config to: {args.output}")
    
    # Create Docker-specific config
    print("\nCreating Docker-specific configuration...")
    
    docker_config_dir = os.path.dirname(args.docker_config)
    
    if not args.dry_run:
        # Create docker config directory
        os.makedirs(docker_config_dir, exist_ok=True)
        
        # Copy entire config directory to preserve other files
        source_dir = os.path.dirname(args.config)
        if os.path.exists(source_dir):
            print(f"Copying config from {source_dir} to {docker_config_dir}")
            # Copy all files except the main config (we'll create that separately)
            for item in os.listdir(source_dir):
                if item == 'opencode.jsonc':
                    continue
                src = os.path.join(source_dir, item)
                dst = os.path.join(docker_config_dir, item)
                if os.path.isfile(src):
                    shutil.copy2(src, dst)
                elif os.path.isdir(src):
                    if os.path.exists(dst):
                        shutil.rmtree(dst)
                    shutil.copytree(src, dst)
    
    # Update config for Docker (this also translates localhost URLs)
    updated_config = update_opencode_config(config, remote_mcps, args.port, args.docker, host_local_mcps)
    
    if args.dry_run:
        mcp_key = 'mcp' if 'mcp' in updated_config else 'mcpServers'
        print(f"\n=== DRY RUN: Docker config {mcp_key} ===")
        print(json.dumps(updated_config.get(mcp_key, {}), indent=2))
    else:
        write_jsonc(args.docker_config, updated_config)
        print(f"✓ Created Docker config: {args.docker_config}")
        print(f"✓ Original config unchanged: {args.config}")
    
    # Show summary
    print("\n=== Configuration Summary ===")
    host = "host.docker.internal" if args.docker else "localhost"
    print(f"mcp-proxy will run on: {host}:{args.port}")
    print("\nEndpoints:")
    for name in list(remote_mcps.keys()) + list(host_local_mcps.keys()):
        print(f"  {name}: http://{host}:{args.port}/servers/{name}/sse")
    
    print("\nNext steps:")
    print(f"  1. Start mcp-proxy: ./manage-mcp-proxy.sh restart")
    print(f"  2. Run OpenCode: ./run-opencode-with-oauth.sh")
    print(f"\nNote: Original config preserved at: {args.config}")
    print(f"      Docker will use: {args.docker_config}")
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
