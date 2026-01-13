# Modern Development Environment with OpenCode
FROM ubuntu:24.04

# Build arguments
ARG OPENCODE_VERSION=latest
ARG DEBIAN_FRONTEND=noninteractive

# Metadata
LABEL maintainer="opencode-docker@example.com"
LABEL description="Comprehensive development environment with OpenCode, modern CLI tools, and multiple shells"
LABEL opencode.version="${OPENCODE_VERSION}"

# ============================================================================
# System packages and base tools
# ============================================================================
RUN apt-get update && apt-get install -y \
    # Core utilities
    curl \
    wget \
    git \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    build-essential \
    # Editors
    vim \
    nano \
    # Shells
    bash \
    zsh \
    fish \
    # Network tools
    netcat-openbsd \
    iputils-ping \
    dnsutils \
    # Process tools
    htop \
    procps \
    # File tools
    tree \
    unzip \
    zip \
    tar \
    gzip \
    bzip2 \
    xz-utils \
    # Development tools
    pkg-config \
    libssl-dev \
    # X11 for clipboard support
    xvfb \
    x11-utils \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Modern CLI tools (Rust-based and others)
# ============================================================================

# Install ripgrep (rg)
RUN ARCH=$(dpkg --print-architecture) && \
    RG_VERSION=$(curl -sL https://api.github.com/repos/BurntSushi/ripgrep/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")') && \
    echo "Installing ripgrep version: ${RG_VERSION}" && \
    if [ "$ARCH" = "amd64" ]; then \
        curl -fsSL --retry 3 "https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/ripgrep_${RG_VERSION}-1_${ARCH}.deb" -o ripgrep.deb && \
        dpkg -i ripgrep.deb && \
        rm ripgrep.deb; \
    else \
        RUST_ARCH=$(uname -m) && \
        curl -fsSL --retry 3 "https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/ripgrep-${RG_VERSION}-${RUST_ARCH}-unknown-linux-gnu.tar.gz" -o ripgrep.tar.gz && \
        tar xzf ripgrep.tar.gz && \
        mv ripgrep-${RG_VERSION}-${RUST_ARCH}-unknown-linux-gnu/rg /usr/local/bin/ && \
        rm -rf ripgrep.tar.gz ripgrep-${RG_VERSION}-${RUST_ARCH}-unknown-linux-gnu; \
    fi

# Install fd-find
RUN ARCH=$(dpkg --print-architecture) && \
    FD_VERSION=$(curl -sL https://api.github.com/repos/sharkdp/fd/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")') && \
    FD_VERSION_NUM=$(echo ${FD_VERSION} | sed 's/^v//') && \
    echo "Installing fd version: ${FD_VERSION}" && \
    curl -fsSL --retry 3 "https://github.com/sharkdp/fd/releases/download/${FD_VERSION}/fd_${FD_VERSION_NUM}_${ARCH}.deb" -o fd.deb && \
    dpkg -i fd.deb && \
    rm fd.deb

# Install bat (better cat)
RUN ARCH=$(dpkg --print-architecture) && \
    BAT_VERSION=$(curl -sL https://api.github.com/repos/sharkdp/bat/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")') && \
    BAT_VERSION_NUM=$(echo ${BAT_VERSION} | sed 's/^v//') && \
    echo "Installing bat version: ${BAT_VERSION}" && \
    curl -fsSL --retry 3 "https://github.com/sharkdp/bat/releases/download/${BAT_VERSION}/bat_${BAT_VERSION_NUM}_${ARCH}.deb" -o bat.deb && \
    dpkg -i bat.deb && \
    rm bat.deb

# Install eza (modern ls)
RUN RUST_ARCH=$(uname -m) && \
    EZA_VERSION=$(curl -sL https://api.github.com/repos/eza-community/eza/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")') && \
    echo "Installing eza version: ${EZA_VERSION}" && \
    curl -fsSL --retry 3 "https://github.com/eza-community/eza/releases/download/${EZA_VERSION}/eza_${RUST_ARCH}-unknown-linux-gnu.tar.gz" -o eza.tar.gz && \
    tar xzf eza.tar.gz && \
    mv eza /usr/local/bin/ && \
    rm eza.tar.gz

# Install delta (better git diff)
RUN ARCH=$(dpkg --print-architecture) && \
    DELTA_VERSION=$(curl -sL https://api.github.com/repos/dandavison/delta/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")') && \
    echo "Installing delta version: ${DELTA_VERSION}" && \
    curl -fsSL --retry 3 "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${ARCH}.deb" -o git-delta.deb && \
    dpkg -i git-delta.deb && \
    rm git-delta.deb

# Install jq and yq
RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*
RUN YQ_VERSION=$(curl -sL https://api.github.com/repos/mikefarah/yq/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")') && \
    ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then ARCH="amd64"; fi && \
    if [ "$ARCH" = "arm64" ]; then ARCH="arm64"; fi && \
    echo "Installing yq version: ${YQ_VERSION}" && \
    curl -fsSL --retry 3 "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH}" -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

# Install tokei (code statistics) - skip for now as v14 doesn't have pre-built binaries
# Can be installed later with: cargo install tokei
RUN echo "tokei: skipped (install with: cargo install tokei)" > /tmp/tokei-note.txt

# Install ast-grep (semantic code search)
RUN ARCH=$(uname -m) && \
    AST_VERSION=$(curl -sL https://api.github.com/repos/ast-grep/ast-grep/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")') && \
    echo "Installing ast-grep version: ${AST_VERSION}" && \
    curl -fsSL --retry 3 "https://github.com/ast-grep/ast-grep/releases/download/${AST_VERSION}/app-${ARCH}-unknown-linux-gnu.zip" -o ast-grep.zip && \
    unzip -q ast-grep.zip && \
    mv sg /usr/local/bin/ && \
    rm ast-grep.zip

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# ============================================================================
# Node.js and npm/npx (for MCP servers)
# ============================================================================
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/* && \
    npm install -g npm@latest

# ============================================================================
# Python and uv
# ============================================================================
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    mv /root/.local/bin/uv /usr/local/bin/ && \
    mv /root/.local/bin/uvx /usr/local/bin/

# Install Python tools via uv
RUN uv tool install pyright && \
    uv tool install ruff && \
    uv tool install black && \
    uv tool install mypy && \
    ln -s /root/.local/bin/pyright /usr/local/bin/pyright && \
    ln -s /root/.local/bin/ruff /usr/local/bin/ruff && \
    ln -s /root/.local/bin/black /usr/local/bin/black && \
    ln -s /root/.local/bin/mypy /usr/local/bin/mypy

# ============================================================================
# Poetry (Python package manager)
# ============================================================================
RUN curl -sSL https://install.python-poetry.org | python3 - && \
    ln -s /root/.local/bin/poetry /usr/local/bin/poetry && \
    poetry config virtualenvs.in-project false && \
    poetry config virtualenvs.path /root/.cache/pypoetry/virtualenvs && \
    poetry self add poetry-plugin-export

# ============================================================================
# Python Virtual Environment Configuration
# ============================================================================
# Store venvs outside project directories to avoid host/container conflicts.
# Host (macOS) keeps .venv in-project, container stores in /root/.cache/...
# This prevents platform-incompatible .venv folders from causing issues.
ENV POETRY_VIRTUALENVS_IN_PROJECT=false
ENV POETRY_VIRTUALENVS_PATH=/root/.cache/pypoetry/virtualenvs
ENV UV_PROJECT_ENVIRONMENT=/root/.cache/uv/venvs

# ============================================================================
# pyenv and additional Python versions (3.8, 3.11)
# ============================================================================
# Install pyenv dependencies and Python package build dependencies
RUN apt-get update && apt-get install -y \
    make \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    llvm \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libffi-dev \
    liblzma-dev \
    # Database libraries
    libpq-dev \
    libleveldb-dev \
    libmysqlclient-dev \
    # Image processing
    libjpeg-dev \
    libpng-dev \
    # XML processing
    libxslt1-dev \
    # Other common dependencies
    libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install pyenv
RUN curl https://pyenv.run | bash && \
    echo 'export PYENV_ROOT="$HOME/.pyenv"' >> /root/.bashrc && \
    echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> /root/.bashrc && \
    echo 'eval "$(pyenv init -)"' >> /root/.bashrc && \
    echo 'export PYENV_ROOT="$HOME/.pyenv"' >> /root/.zshrc && \
    echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> /root/.zshrc && \
    echo 'eval "$(pyenv init -)"' >> /root/.zshrc && \
    echo 'set -gx PYENV_ROOT "$HOME/.pyenv"' >> /root/.config/fish/config.fish && \
    echo 'set -gx PATH "$PYENV_ROOT/bin" $PATH' >> /root/.config/fish/config.fish && \
    echo 'status is-interactive; and pyenv init - | source' >> /root/.config/fish/config.fish

# Install Python 3.8, 3.9, and 3.11 via pyenv
ENV PYENV_ROOT="/root/.pyenv"
ENV PATH="$PYENV_ROOT/bin:$PATH"
ENV PATH="$PYENV_ROOT/shims:$PATH"
RUN eval "$(pyenv init -)" && \
    pyenv install 3.8.18 && \
    pyenv install 3.9.18 && \
    pyenv install 3.11.9 && \
    pyenv global system 3.11.9 3.9.18 3.8.18 && \
    echo "Python versions installed: $(pyenv versions)"

# ============================================================================
# Additional development tools
# ============================================================================

# Install shellcheck
RUN apt-get update && apt-get install -y shellcheck && rm -rf /var/lib/apt/lists/*

# Install semgrep
RUN curl -L "https://github.com/returntocorp/semgrep/releases/latest/download/semgrep-linux-$(uname -m)" -o /usr/local/bin/semgrep && \
    chmod +x /usr/local/bin/semgrep

# ============================================================================
# Graphing and Visualization Tools
# ============================================================================

# Install Graphviz (for DOT language graph rendering)
RUN apt-get update && apt-get install -y graphviz && rm -rf /var/lib/apt/lists/*

# Install Mermaid CLI (for Mermaid diagram rendering)
RUN npm install -g @mermaid-js/mermaid-cli

# Install PlantUML (Java-based UML and diagram tool)
RUN apt-get update && apt-get install -y default-jre && rm -rf /var/lib/apt/lists/* && \
    curl -L "https://github.com/plantuml/plantuml/releases/latest/download/plantuml.jar" -o /usr/local/bin/plantuml.jar && \
    echo '#!/bin/bash\njava -jar /usr/local/bin/plantuml.jar "$@"' > /usr/local/bin/plantuml && \
    chmod +x /usr/local/bin/plantuml

# Install D2 (modern diagram scripting language)
RUN D2_VERSION=$(curl -sL https://api.github.com/repos/terrastruct/d2/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")') && \
    ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then ARCH="amd64"; fi && \
    if [ "$ARCH" = "arm64" ]; then ARCH="arm64"; fi && \
    echo "Installing d2 version: ${D2_VERSION}" && \
    curl -fsSL --retry 3 "https://github.com/terrastruct/d2/releases/download/${D2_VERSION}/d2-${D2_VERSION}-linux-${ARCH}.tar.gz" -o d2.tar.gz && \
    tar xzf d2.tar.gz && \
    mv d2-${D2_VERSION}/bin/d2 /usr/local/bin/ && \
    rm -rf d2.tar.gz d2-${D2_VERSION}

# Install Mermaid filter for Pandoc (if using markdown -> diagram workflows)
RUN npm install -g mermaid-filter

# Install diagram generation Python tools via uv
RUN uv tool install diagrams && \
    ln -s /root/.local/bin/diagrams /usr/local/bin/diagrams 2>/dev/null || true

# Install graphviz Python bindings and other graph libraries
RUN uv pip install --system graphviz networkx matplotlib pydot pygraphviz 2>/dev/null || \
    echo "Note: Some Python graph libraries may need additional system dependencies"

# ============================================================================
# Shell configurations
# ============================================================================

# Set up zsh with oh-my-zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Set up fish with fisher
RUN fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"

# Configure git to use delta
RUN git config --global core.pager "delta" && \
    git config --global interactive.diffFilter "delta --color-only" && \
    git config --global delta.navigate true && \
    git config --global delta.light false && \
    git config --global merge.conflictstyle diff3 && \
    git config --global diff.colorMoved default

# Add GitHub to known_hosts to avoid SSH host key verification prompts
RUN mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh && \
    ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> /root/.ssh/known_hosts 2>/dev/null && \
    chmod 644 /root/.ssh/known_hosts && \
    echo "GitHub SSH host keys added to known_hosts"

# Add useful aliases to bashrc
RUN echo 'alias ll="eza -la --git"' >> /root/.bashrc && \
    echo 'alias ls="eza"' >> /root/.bashrc && \
    echo 'alias cat="bat"' >> /root/.bashrc && \
    echo 'alias find="fd"' >> /root/.bashrc && \
    echo 'alias grep="rg"' >> /root/.bashrc && \
    echo 'export PATH="/usr/local/bin:$PATH"' >> /root/.bashrc

# Add aliases to zshrc
RUN echo 'alias ll="eza -la --git"' >> /root/.zshrc && \
    echo 'alias ls="eza"' >> /root/.zshrc && \
    echo 'alias cat="bat"' >> /root/.zshrc && \
    echo 'alias find="fd"' >> /root/.zshrc && \
    echo 'alias grep="rg"' >> /root/.zshrc && \
    echo 'export PATH="/usr/local/bin:$PATH"' >> /root/.zshrc

# Add aliases to fish config
RUN mkdir -p /root/.config/fish && \
    echo 'alias ll="eza -la --git"' >> /root/.config/fish/config.fish && \
    echo 'alias ls="eza"' >> /root/.config/fish/config.fish && \
    echo 'alias cat="bat"' >> /root/.config/fish/config.fish && \
    echo 'alias find="fd"' >> /root/.config/fish/config.fish && \
    echo 'alias grep="rg"' >> /root/.config/fish/config.fish && \
    echo 'set -gx PATH /usr/local/bin $PATH' >> /root/.config/fish/config.fish

# ============================================================================
# OpenCode installation
# ============================================================================
RUN npm install -g opencode-ai@latest && \
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
# Install xclip first (OpenCode prefers xclip over xsel for images)
RUN apt-get update && apt-get install -y xclip && rm -rf /var/lib/apt/lists/*

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
# Final setup
# ============================================================================

# Set working directory
WORKDIR /workspace

# Set default shell to bash (but zsh and fish are available)
ENV SHELL=/bin/bash

# Verify installations
RUN echo "=== Installed Tools ===" && \
    echo "OpenCode: $(cat /etc/opencode-version)" && \
    echo "Node: $(node --version)" && \
    echo "npm: $(npm --version)" && \
    echo "uv: $(uv --version)" && \
    echo "poetry: $(poetry --version)" && \
    echo "Python: $(uv run python --version 2>&1 || echo 'via uv')" && \
    echo "ripgrep: $(rg --version | head -1)" && \
    echo "fd: $(fd --version)" && \
    echo "bat: $(bat --version)" && \
    echo "eza: $(eza --version | head -1)" && \
    echo "delta: $(delta --version)" && \
    echo "jq: $(jq --version)" && \
    echo "yq: $(yq --version)" && \
    echo "gh: $(gh --version | head -1)" && \
    echo "ast-grep: $(sg --version)" && \
    echo "tokei: $(tokei --version)" && \
    echo "pyright: $(pyright --version)" && \
    echo "ruff: $(ruff --version)" && \
    echo "shellcheck: $(shellcheck --version | head -2 | tail -1)" && \
    echo "semgrep: $(semgrep --version)" && \
    echo "graphviz: $(dot -V 2>&1)" && \
    echo "mermaid: $(mmdc --version)" && \
    echo "plantuml: $(plantuml -version | head -1)" && \
    echo "d2: $(d2 --version)" && \
    echo "======================="

# Default command - run opencode via entrypoint (starts Xvfb for clipboard)
CMD ["opencode-entrypoint"]
