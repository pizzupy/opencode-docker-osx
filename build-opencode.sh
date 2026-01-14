#!/bin/bash
# Build the OpenCode layer on top of the base image
# This can be built frequently for OpenCode updates (much faster!)

set -e

BASE_IMAGE="${BASE_IMAGE:-opencode-base:latest}"
IMAGE_NAME="${IMAGE_NAME:-opencode-dev}"
TAG="${TAG:-latest}"
OPENCODE_VERSION="${OPENCODE_VERSION:-latest}"

echo "Building OpenCode image: ${IMAGE_NAME}:${TAG}"
echo "Base image: ${BASE_IMAGE}"
echo "OpenCode version: ${OPENCODE_VERSION}"
echo ""

# Check if base image exists
if ! docker image inspect "${BASE_IMAGE}" >/dev/null 2>&1; then
    echo "ERROR: Base image '${BASE_IMAGE}' not found!"
    echo "Please build it first: ./build-base.sh"
    exit 1
fi

docker build \
    -f Dockerfile \
    --build-arg OPENCODE_VERSION="${OPENCODE_VERSION}" \
    -t "${IMAGE_NAME}:${TAG}" \
    .

echo ""
echo "✓ OpenCode image built successfully: ${IMAGE_NAME}:${TAG}"
echo ""
echo "Next steps:"
echo "  1. Run with docker-compose: docker-compose up -d"
echo "  2. Or run directly: docker run -it ${IMAGE_NAME}:${TAG}"
echo ""
echo "To update OpenCode in the future:"
echo "  OPENCODE_VERSION=1.2.3 ./build-opencode.sh"
