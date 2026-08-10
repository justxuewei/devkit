#!/bin/bash
# Build + push a MULTI-ARCH image (linux/amd64 + linux/arm64) so the aarch64 rund
# board and x86 hosts both work off the same :latest tag.
#
# Run on any host with docker + buildx + internet (native arch doesn't matter --
# buildx cross-builds the other arch under qemu). It self-installs the qemu
# emulators and a buildx container builder, then prompts for `docker login`.
#
# Overrides: PLATFORMS=linux/arm64 (arm-only), TAG=..., BUILDER=...,
# PROXY_URL=... (empty disables proxying), NO_PROXY=...

CUR_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

set -euo pipefail

IMAGE_NAME="niuxuewei/myubuntu-pub"
REGISTRY="reg.antgroup-inc.cn"
TAG="${TAG:-latest}"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
BUILDER="${BUILDER:-mrbuilder-proxy}"
PROXY_URL="${PROXY_URL-http://127.0.0.1:7890}"
NO_PROXY="${NO_PROXY-*.aliyuncs.com}"

echo "==> Registering qemu binfmt emulators (needed to cross-build; no-op if present)"
docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null 2>&1 \
    || echo "    (skipped; assuming emulators already registered)"

echo "==> Ensuring buildx container builder '${BUILDER}' (required for multi-arch)"
if ! docker buildx inspect "${BUILDER}" >/dev/null 2>&1; then
    builder_args=(
        --name "${BUILDER}"
        --driver docker-container
        --driver-opt network=host
        --buildkitd-config "${CUR_PATH}/buildkitd.toml"
    )
    if [[ -n "${PROXY_URL}" ]]; then
        builder_args+=(
            --driver-opt "env.HTTP_PROXY=${PROXY_URL}"
            --driver-opt "env.HTTPS_PROXY=${PROXY_URL}"
            --driver-opt "env.NO_PROXY=${NO_PROXY}"
            --driver-opt "env.http_proxy=${PROXY_URL}"
            --driver-opt "env.https_proxy=${PROXY_URL}"
            --driver-opt "env.no_proxy=${NO_PROXY}"
        )
    fi
    docker buildx create "${builder_args[@]}" --bootstrap
fi
docker buildx use "${BUILDER}"

echo "==> Logging in to ${REGISTRY}"
docker login "${REGISTRY}"

echo "==> Building + pushing ${FULL_IMAGE} for ${PLATFORMS}"
build_args=()
if [[ -n "${PROXY_URL}" ]]; then
    build_args+=(
        --build-arg "HTTP_PROXY=${PROXY_URL}"
        --build-arg "HTTPS_PROXY=${PROXY_URL}"
        --build-arg "NO_PROXY=${NO_PROXY}"
        --build-arg "http_proxy=${PROXY_URL}"
        --build-arg "https_proxy=${PROXY_URL}"
        --build-arg "no_proxy=${NO_PROXY}"
    )
fi

docker buildx build "${build_args[@]}" \
    --platform "${PLATFORMS}" \
    -t "${FULL_IMAGE}" \
    --push \
    "${CUR_PATH}"

echo "==> Done: ${FULL_IMAGE} (${PLATFORMS})"
