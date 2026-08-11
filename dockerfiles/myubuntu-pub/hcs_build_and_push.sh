#!/bin/bash
# Build + push a MULTI-ARCH image (linux/amd64 + linux/arm64) so the aarch64 rund
# board and x86 hosts both work off the same :latest tag.
#
# Run on any host with docker + buildx + internet (native arch doesn't matter --
# buildx cross-builds the other arch under qemu). It self-installs the qemu
# emulators and a buildx container builder, then prompts for `docker login`.
#
# Overrides: PLATFORMS=linux/arm64 (arm-only), TAG=..., BUILDER=...

CUR_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

set -euo pipefail

IMAGE_NAME="niuxuewei/myubuntu-pub"
REGISTRY="reg.antgroup-inc.cn"
TAG="${TAG:-latest}"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
BUILDER="${BUILDER:-mrbuilder}"

echo "==> Registering qemu binfmt emulators (needed to cross-build; no-op if present)"
docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null 2>&1 \
    || echo "    (skipped; assuming emulators already registered)"

echo "==> Ensuring buildx container builder '${BUILDER}' (required for multi-arch)"
docker buildx inspect "${BUILDER}" >/dev/null 2>&1 \
    || docker buildx create --name "${BUILDER}" --driver docker-container --bootstrap
docker buildx use "${BUILDER}"

echo "==> Logging in to ${REGISTRY}"
docker login "${REGISTRY}"

echo "==> Building + pushing ${FULL_IMAGE} for ${PLATFORMS}"
docker buildx build \
    --platform "${PLATFORMS}" \
    -t "${FULL_IMAGE}" \
    --push \
    "${CUR_PATH}"

echo "==> Done: ${FULL_IMAGE} (${PLATFORMS})"
