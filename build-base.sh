#!/bin/bash
# Build the base development environment image
# This should be built infrequently (quarterly or when tools need updates)

set -e

IMAGE_NAME="${IMAGE_NAME:-opencode-base}"
TAG="${TAG:-latest}"

echo "Building base image: ${IMAGE_NAME}:${TAG}"
echo "This may take 10-15 minutes on first build..."
echo ""

docker build \
    -f Dockerfile.base \
    -t "${IMAGE_NAME}:${TAG}" \
    .

echo ""
echo "✓ Base image built successfully: ${IMAGE_NAME}:${TAG}"
echo ""
echo "Next steps:"
echo "  1. Build OpenCode layer: ./build-opencode.sh"
echo "  2. Or build both: ./build-all.sh"
echo ""
echo "Optional: Push to registry for sharing:"
echo "  docker tag ${IMAGE_NAME}:${TAG} your-registry/${IMAGE_NAME}:${TAG}"
echo "  docker push your-registry/${IMAGE_NAME}:${TAG}"
