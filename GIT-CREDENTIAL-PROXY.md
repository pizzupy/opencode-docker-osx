# Git Credential Proxy for macOS Keychain

This feature allows Git operations inside Docker containers to seamlessly access credentials stored in your macOS Keychain.

## Overview

When you run `git clone`, `git push`, or other Git operations that require authentication inside the container, they will automatically retrieve credentials from your macOS Keychain without prompting you.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Docker Container                                             │
│                                                              │
│  ┌──────────┐         ┌─────────────────────────────────┐  │
│  │   git    │ ──────> │ git-credential-helper           │  │
│  │ command  │         │ /usr/local/bin/git-credential-  │  │
│  └──────────┘         │ helper (Python script)          │  │
│                       └─────────────────────────────────┘  │
│                                 │                           │
│                                 │ Unix Socket               │
└─────────────────────────────────┼───────────────────────────┘
                                  │
                                  │ /tmp/git-credential-proxy.sock
                                  │
┌─────────────────────────────────┼───────────────────────────┐
│ macOS Host                      │                           │
│                                 ▼                           │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ git-credential-proxy.py                              │  │
│  │ (Python service listening on Unix socket)            │  │
│  └──────────────────────────────────────────────────────┘  │
│                                 │                           │
│                                 ▼                           │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ git credential-osxkeychain                           │  │
│  │ (macOS native credential helper)                     │  │
│  └──────────────────────────────────────────────────────┘  │
│                                 │                           │
│                                 ▼                           │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ macOS Keychain                                       │  │
│  │ (Stores GitHub, GitLab, etc. credentials)            │  │
│  └──────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────┘
```

## Components

### 1. Host-side Proxy (`lib/git-credential-proxy.py`)

A Python service that:
- Listens on a Unix socket (`/tmp/git-credential-proxy.sock`)
- Receives git credential requests from containers
- Forwards them to macOS `git credential-osxkeychain`
- Returns credentials back to the container

**Protocol:**
```
Request:  <operation>\n<git-credential-data>\n\n
Response: <git-credential-data>\n\n
```

Where `<operation>` is one of: `get`, `store`, `erase`

### 2. Container-side Helper (`lib/git-credential-helper`)

A Python script installed in the container at `/usr/local/bin/git-credential-helper` that:
- Implements the git credential helper protocol
- Connects to the host proxy via Unix socket
- Forwards credential requests and returns responses

### 3. Integration

- **Dockerfile**: Installs the helper and configures git to use it
- **docker-compose.yml**: Mounts the Unix socket into the container
- **run-opencode.sh**: Starts/stops the proxy automatically

## Usage

### Enabling the Feature

The git credential proxy is **disabled by default**. To enable it, set the environment variable:

```bash
export ENABLE_GIT_CREDENTIAL_PROXY=true
./run-opencode.sh
```

Or enable it for a single run:

```bash
ENABLE_GIT_CREDENTIAL_PROXY=true ./run-opencode.sh
```

To make it permanent, add to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.):

```bash
export ENABLE_GIT_CREDENTIAL_PROXY=true
```

### Using Git with Keychain Credentials

Once enabled, git operations inside the container will automatically use your macOS Keychain credentials:

```bash
# Inside container
git clone https://github.com/your-org/private-repo.git
git push origin main
```

Credentials will be automatically retrieved from your macOS Keychain without prompting.

### Manual Testing

To test the proxy manually without running the full container:

```bash
# Start the proxy
python3 lib/git-credential-proxy.py /tmp/git-credential-proxy.sock

# In another terminal, test it
./test-git-credential-proxy.sh
```

### Using with docker-compose

If you use `docker-compose` directly instead of `run-opencode.sh`, you need to:

1. Start the proxy manually:
   ```bash
   python3 lib/git-credential-proxy.py /tmp/git-credential-proxy.sock &
   ```

2. Uncomment the git credential lines in `docker-compose.yml`:
   ```yaml
   volumes:
     - /tmp/git-credential-proxy.sock:/tmp/git-credential-proxy.sock
   
   environment:
     - GIT_CREDENTIAL_SOCK=/tmp/git-credential-proxy.sock
   ```

3. Run docker-compose:
   ```bash
   docker-compose up
   ```

### Storing Credentials in Keychain

If you don't have credentials in your macOS Keychain yet, you can add them:

**Option 1: Use git on macOS**
```bash
# On your Mac (outside container)
git config --global credential.helper osxkeychain
git clone https://github.com/your-org/private-repo.git
# Enter credentials when prompted - they'll be saved to Keychain
```

**Option 2: Use Keychain Access app**
1. Open "Keychain Access" app
2. Click the "+" button to add a new password
3. Set:
   - Keychain Item Name: `https://github.com`
   - Account Name: your GitHub username
   - Password: your GitHub personal access token

## Supported Services

This works with any service that git can authenticate to:
- GitHub (https://github.com)
- GitLab (https://gitlab.com)
- Bitbucket (https://bitbucket.org)
- Any other git hosting service

## Security

- **Unix socket**: Communication between container and host uses a Unix socket, which is more secure than network communication
- **No credential storage in container**: Credentials are never stored in the container filesystem
- **macOS Keychain protection**: Credentials remain protected by macOS Keychain's security features
- **Process isolation**: The proxy runs as a separate process and can be independently managed

## Troubleshooting

### Credentials not found

If git prompts for credentials inside the container:

1. **Check if proxy is running:**
   ```bash
   # On macOS host
   ls -la /tmp/git-credential-proxy.sock
   ```

2. **Check if credentials exist in Keychain:**
   ```bash
   # On macOS host
   security find-internet-password -s github.com
   ```

3. **Test the proxy:**
   ```bash
   ./test-git-credential-proxy.sh
   ```

4. **Check proxy logs:**
   ```bash
   # If started by run-opencode.sh, check container logs
   docker logs opencode-*
   ```

### Socket permission errors

If you see socket permission errors:

```bash
# On macOS host
chmod 666 /tmp/git-credential-proxy.sock
```

### Proxy won't start

Check if another instance is running:

```bash
# On macOS host
ps aux | grep git-credential-proxy
kill <PID>  # if found
rm /tmp/git-credential-proxy.sock
```

## Limitations

- **macOS only**: This solution is specific to macOS and its Keychain
- **HTTPS only**: Works with HTTPS git URLs (not SSH)
- **Single user**: Designed for single-user development environments

## Future Enhancements

Potential improvements:
- Support for Linux secret services (gnome-keyring, KWallet)
- Support for Windows Credential Manager
- Credential caching to reduce Keychain queries
- Audit logging of credential access
- Support for multiple credential backends

## Related Files

- `lib/git-credential-proxy.py` - Host-side proxy service
- `lib/git-credential-helper` - Container-side helper script
- `test-git-credential-proxy.sh` - Test script
- `Dockerfile` - Container configuration
- `docker-compose.yml` - Volume mounts
- `run-opencode.sh` - Proxy lifecycle management
