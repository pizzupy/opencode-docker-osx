#!/usr/bin/env bash
#
# update-opencode.sh - Check for OpenCode updates and rebuild Docker image if needed
#
# Usage:
#   ./update-opencode.sh           # Check and update if needed
#   ./update-opencode.sh --force   # Force rebuild regardless of version
#   ./update-opencode.sh --check   # Only check, don't build
#

set -euo pipefail

# Configuration
GITHUB_REPO="sst/opencode"
IMAGE_NAME="opencode-dev"
VERSION_FILE=".opencode-version"
DOCKERFILE="Dockerfile"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check if required commands are available
check_requirements() {
    local missing=()
    
    for cmd in curl jq docker; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing[*]}"
        log_info "Please install them and try again"
        exit 1
    fi
}

# Get latest release version from GitHub
get_latest_version() {
    # Log to stderr so it doesn't interfere with return value
    log_info "Fetching latest OpenCode release from GitHub..." >&2
    
    local response
    response=$(curl -sL --max-time 30 --retry 3 "https://api.github.com/repos/${GITHUB_REPO}/releases/latest")
    
    if [ -z "$response" ]; then
        log_error "Failed to fetch release information from GitHub"
        exit 1
    fi
    
    local version
    version=$(echo "$response" | jq -r '.tag_name')
    
    if [ "$version" = "null" ] || [ -z "$version" ]; then
        log_error "Could not parse version from GitHub API response"
        exit 1
    fi
    
    echo "$version"
}

# Get currently installed version
get_current_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE"
    else
        echo "none"
    fi
}

# Build Docker image
build_image() {
    local version=$1
    
    log_info "Building Docker image with OpenCode version: $version"
    log_info "This may take several minutes..."
    
    if docker build \
        --build-arg OPENCODE_VERSION="$version" \
        -t "${IMAGE_NAME}:${version}" \
        -t "${IMAGE_NAME}:latest" \
        -f "$DOCKERFILE" \
        .; then
        
        log_success "Docker image built successfully"
        echo "$version" > "$VERSION_FILE"
        log_info "Version file updated: $VERSION_FILE"
        return 0
    else
        log_error "Docker build failed"
        return 1
    fi
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Check for OpenCode updates and rebuild Docker image if needed.

OPTIONS:
    --force     Force rebuild regardless of current version
    --check     Only check for updates, don't build
    --help      Show this help message

EXAMPLES:
    $0              # Check and update if needed
    $0 --force      # Force rebuild
    $0 --check      # Just check for updates

EOF
}

# Main function
main() {
    local force_build=false
    local check_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force_build=true
                shift
                ;;
            --check)
                check_only=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Check requirements
    check_requirements
    
    # Get versions
    local latest_version
    latest_version=$(get_latest_version)
    
    local current_version
    current_version=$(get_current_version)
    
    log_info "Current version: $current_version"
    log_info "Latest version:  $latest_version"
    
    # Check if update is needed
    if [ "$current_version" = "$latest_version" ] && [ "$force_build" = false ]; then
        log_success "Already up to date!"
        
        # Check if image exists
        if ! docker image inspect "${IMAGE_NAME}:latest" &> /dev/null; then
            log_warning "Docker image not found locally. Building..."
            build_image "$latest_version"
        fi
        
        exit 0
    fi
    
    if [ "$check_only" = true ]; then
        if [ "$current_version" != "$latest_version" ]; then
            log_warning "Update available: $current_version -> $latest_version"
            exit 1
        else
            log_success "Already up to date!"
            exit 0
        fi
    fi
    
    # Build the image
    if [ "$force_build" = true ]; then
        log_info "Force build requested"
    else
        log_info "Update available: $current_version -> $latest_version"
    fi
    
    if build_image "$latest_version"; then
        log_success "OpenCode development environment is ready!"
        log_info "Run with: docker run -it --rm -v \$(pwd):/workspace ${IMAGE_NAME}:latest"
    else
        exit 1
    fi
}

# Run main function
main "$@"
