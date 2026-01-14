# OpenCode Development Environment
# Built on top of opencode-base for fast, independent updates
FROM opencode-base:latest

# Build arguments
ARG OPENCODE_VERSION=latest

# Metadata
LABEL maintainer="opencode-docker@example.com"
LABEL description="OpenCode AI development environment with clipboard and OAuth integration"
LABEL opencode.version="${OPENCODE_VERSION}"
LABEL layer="opencode"

# ============================================================================
# OpenCode installation
# ============================================================================
RUN npm install -g opencode-ai@${OPENCODE_VERSION} && \
    OPENCODE_VERSION=$(opencode --version 2>&1 | head -1 || echo "unknown") && \
    echo "$OPENCODE_VERSION" > /etc/opencode-version && \
    echo "OpenCode installed successfully: $OPENCODE_VERSION"

# ============================================================================
# URL Bridge Setup (for OAuth and browser opening from container)
# ============================================================================
COPY lib/container-open-wrapper.sh /usr/local/bin/container-open-wrapper
COPY lib/patch-npm-open.sh /usr/local/bin/patch-npm-open
RUN chmod +x /usr/local/bin/container-open-wrapper && \
    chmod +x /usr/local/bin/patch-npm-open && \
    ln -sf /usr/local/bin/container-open-wrapper /usr/local/bin/open && \
    ln -sf /usr/local/bin/container-open-wrapper /usr/local/bin/xdg-open && \
    echo "URL bridge wrapper installed (open, xdg-open)"

# ============================================================================
# Clipboard Bridge Setup (for macOS clipboard → container paste support)
# ============================================================================
# Install xclip wrapper that reads from /shared/clipboard bridge
COPY lib/xclip-wrapper.sh /usr/local/bin/xclip-wrapper
RUN chmod +x /usr/local/bin/xclip-wrapper && \
    # Move real xclip out of the way
    mv /usr/bin/xclip /usr/bin/xclip.real && \
    # Install our wrapper as xclip
    ln -sf /usr/local/bin/xclip-wrapper /usr/bin/xclip && \
    echo "Clipboard bridge wrapper installed (xclip)"

# Install xsel wrapper that reads from /shared/clipboard bridge
COPY lib/xsel-wrapper.sh /usr/local/bin/xsel-wrapper
RUN chmod +x /usr/local/bin/xsel-wrapper && \
    # Move real xsel out of the way (if it exists)
    if [ -f /usr/bin/xsel ]; then \
        mv /usr/bin/xsel /usr/bin/xsel.real; \
    fi && \
    # Install our wrapper as xsel
    ln -sf /usr/local/bin/xsel-wrapper /usr/bin/xsel && \
    echo "Clipboard bridge wrapper installed (xsel)"

# Install OpenCode entrypoint (TTY-preserving with exec)
COPY lib/opencode-entrypoint-tty.sh /usr/local/bin/opencode-entrypoint-tty
RUN chmod +x /usr/local/bin/opencode-entrypoint-tty

# Install git credential helper for macOS Keychain proxy
COPY lib/git-credential-helper /usr/local/bin/git-credential-helper
RUN chmod +x /usr/local/bin/git-credential-helper && \
    git config --system credential.helper /usr/local/bin/git-credential-helper

# ============================================================================
# Final verification
# ============================================================================
RUN echo "=== OpenCode Layer ===" && \
    echo "OpenCode: $(cat /etc/opencode-version)" && \
    echo "======================"

# Set working directory
WORKDIR /workspace

# Default command - run opencode via entrypoint (starts Xvfb for clipboard)
CMD ["opencode-entrypoint"]
