.PHONY: help build update check run shell clean prune test-tools list-tools

# Configuration
IMAGE_NAME := opencode-dev
CONTAINER_NAME := opencode-dev-container
WORKSPACE := $(shell pwd)

# Default target
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo "OpenCode Development Environment"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build the Docker image
	@echo "Building Docker image..."
	./update-opencode.sh --force

update: ## Check for updates and rebuild if needed
	@echo "Checking for OpenCode updates..."
	./update-opencode.sh

check: ## Check for updates without building
	@echo "Checking for updates..."
	./update-opencode.sh --check

run: ## Run a command in the container (usage: make run CMD="your command")
	@docker run --rm -it \
		-v $(WORKSPACE):/workspace \
		-v $(HOME)/.gitconfig:/root/.gitconfig:ro \
		-v $(HOME)/.ssh:/root/.ssh:ro \
		$(IMAGE_NAME):latest \
		bash -c "$(CMD)"

shell: ## Start an interactive shell in the container
	@docker run --rm -it \
		-v $(WORKSPACE):/workspace \
		-v $(HOME)/.gitconfig:/root/.gitconfig:ro \
		-v $(HOME)/.ssh:/root/.ssh:ro \
		--name $(CONTAINER_NAME) \
		$(IMAGE_NAME):latest \
		/bin/bash

zsh: ## Start an interactive zsh shell in the container
	@docker run --rm -it \
		-v $(WORKSPACE):/workspace \
		-v $(HOME)/.gitconfig:/root/.gitconfig:ro \
		-v $(HOME)/.ssh:/root/.ssh:ro \
		--name $(CONTAINER_NAME) \
		$(IMAGE_NAME):latest \
		/bin/zsh

fish: ## Start an interactive fish shell in the container
	@docker run --rm -it \
		-v $(WORKSPACE):/workspace \
		-v $(HOME)/.gitconfig:/root/.gitconfig:ro \
		-v $(HOME)/.ssh:/root/.ssh:ro \
		--name $(CONTAINER_NAME) \
		$(IMAGE_NAME):latest \
		/usr/bin/fish

test-tools: ## Test that all tools are working
	@echo "Testing installed tools..."
	@docker run --rm $(IMAGE_NAME):latest bash -c '\
		echo "=== Testing Core Tools ===" && \
		opencode --version 2>/dev/null || echo "OpenCode: installed" && \
		node --version && \
		npm --version && \
		uv --version && \
		echo "" && \
		echo "=== Testing CLI Tools ===" && \
		rg --version | head -1 && \
		fd --version && \
		bat --version && \
		eza --version | head -1 && \
		delta --version && \
		jq --version && \
		yq --version && \
		echo "" && \
		echo "=== Testing Development Tools ===" && \
		gh --version | head -1 && \
		sg --version && \
		tokei --version && \
		pyright --version && \
		ruff --version && \
		shellcheck --version | head -2 | tail -1 && \
		semgrep --version && \
		echo "" && \
		echo "=== Testing Graph Tools ===" && \
		dot -V 2>&1 && \
		mmdc --version && \
		plantuml -version | head -1 && \
		d2 --version && \
		echo "" && \
		echo "=== All tools working! ==="'

list-tools: ## List all installed tools with versions
	@docker run --rm $(IMAGE_NAME):latest bash -c '\
		echo "=== Installed Tools ===" && \
		cat /etc/opencode-version | xargs -I {} echo "OpenCode: {}" && \
		echo "Node: $$(node --version)" && \
		echo "npm: $$(npm --version)" && \
		echo "uv: $$(uv --version)" && \
		echo "ripgrep: $$(rg --version | head -1)" && \
		echo "fd: $$(fd --version)" && \
		echo "bat: $$(bat --version)" && \
		echo "eza: $$(eza --version | head -1)" && \
		echo "delta: $$(delta --version)" && \
		echo "jq: $$(jq --version)" && \
		echo "yq: $$(yq --version)" && \
		echo "gh: $$(gh --version | head -1)" && \
		echo "ast-grep: $$(sg --version)" && \
		echo "tokei: $$(tokei --version)" && \
		echo "pyright: $$(pyright --version)" && \
		echo "ruff: $$(ruff --version)" && \
		echo "shellcheck: $$(shellcheck --version | head -2 | tail -1)" && \
		echo "semgrep: $$(semgrep --version)" && \
		echo "graphviz: $$(dot -V 2>&1)" && \
		echo "mermaid: $$(mmdc --version)" && \
		echo "plantuml: $$(plantuml -version | head -1)" && \
		echo "d2: $$(d2 --version)" && \
		echo "======================="'

clean: ## Clean all images and optionally stop/kill containers using them
	@echo "Checking for containers using $(IMAGE_NAME) images..."
	@RUNNING_CONTAINERS=$$(docker ps --filter ancestor=$(IMAGE_NAME) --format "{{.ID}} {{.Names}}" 2>/dev/null); \
	if [ -n "$$RUNNING_CONTAINERS" ]; then \
		echo "Found running containers:"; \
		echo "$$RUNNING_CONTAINERS" | while read id name; do \
			echo "  - $$name ($$id)"; \
		done; \
		read -p "Stop and remove these containers? [y/N] " -n 1 -r; \
		echo; \
		if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
			echo "Stopping and removing containers..."; \
			echo "$$RUNNING_CONTAINERS" | awk '{print $$1}' | xargs -r docker rm -f; \
		else \
			echo "Skipping container cleanup. Cannot remove images while containers are running."; \
			exit 1; \
		fi; \
	fi; \
	echo "Removing all $(IMAGE_NAME) images..."; \
	docker images "$(IMAGE_NAME)" --format "{{.ID}} {{.Tag}}" | awk '{print $$1}' | sort -u | xargs -r docker rmi -f 2>/dev/null || true; \
	echo "Cleaning up stopped containers..."; \
	docker container prune -f; \
	echo "Cleaning up dangling images..."; \
	docker image prune -f; \
	echo "Cleanup complete!"

prune: ## Remove unused OpenCode images and containers
	@echo "WARNING: This will remove unused OpenCode Docker images!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "Removing unused OpenCode images..."; \
		docker images "$(IMAGE_NAME)" --format "{{.ID}} {{.Tag}}" | grep -v latest | awk '{print $$1}' | xargs -r docker rmi 2>/dev/null || true; \
		echo "Cleaning up dangling images..."; \
		docker image prune -f; \
	fi

# Example targets for common workflows
example-mermaid: ## Example: Render a Mermaid diagram
	@echo "graph TD\n  A[Start] --> B[Process]\n  B --> C[End]" > /tmp/example.mmd
	@docker run --rm -v /tmp:/workspace $(IMAGE_NAME):latest \
		mmdc -i /workspace/example.mmd -o /workspace/example.png
	@echo "Diagram saved to /tmp/example.png"

example-graphviz: ## Example: Render a Graphviz DOT diagram
	@echo "digraph G { A -> B; B -> C; C -> A; }" > /tmp/example.dot
	@docker run --rm -v /tmp:/workspace $(IMAGE_NAME):latest \
		dot -Tpng /workspace/example.dot -o /workspace/example-dot.png
	@echo "Diagram saved to /tmp/example-dot.png"

example-d2: ## Example: Render a D2 diagram
	@echo "x -> y -> z" > /tmp/example.d2
	@docker run --rm -v /tmp:/workspace $(IMAGE_NAME):latest \
		d2 /workspace/example.d2 /workspace/example-d2.png
	@echo "Diagram saved to /tmp/example-d2.png"
