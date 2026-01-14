#!/bin/bash
# Build both base and OpenCode images in sequence
# Use this for initial setup or when both need rebuilding

set -e

echo "=========================================="
echo "Building complete OpenCode environment"
echo "=========================================="
echo ""

# Build base first
echo "Step 1/2: Building base image..."
echo ""
./build-base.sh

echo ""
echo "=========================================="
echo ""

# Build OpenCode layer
echo "Step 2/2: Building OpenCode layer..."
echo ""
./build-opencode.sh

echo ""
echo "=========================================="
echo "✓ Complete build finished successfully!"
echo "=========================================="
echo ""
echo "Images created:"
echo "  - opencode-base:latest  (~2.5GB, update rarely)"
echo "  - opencode-dev:latest   (~100MB on top of base, update frequently)"
echo ""
echo "Start using:"
echo "  docker-compose up -d"
