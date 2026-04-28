#!/bin/bash

CUR_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

set -euo pipefail

IMAGE_NAME="niuxuewei/myubuntu"
REGISTRY="reg.antgroup-inc.cn"
TAG="latest"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"

cp ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa ~/.ssh/id_rsa.pub "${CUR_PATH}"

echo "==> Building image: ${FULL_IMAGE}"
sudo docker build -t "${FULL_IMAGE}" "${CUR_PATH}"

echo "==> Logging in to Docker Hub"
sudo docker login "${REGISTRY}"

echo "==> Pushing image: ${FULL_IMAGE}"
sudo docker push "${FULL_IMAGE}"

echo "==> Done: ${FULL_IMAGE}"

rm -rf "${CUR_PATH}/id_ed25519" "${CUR_PATH}/id_ed25519.pub" "${CUR_PATH}/id_rsa" "${CUR_PATH}/id_rsa.pub"
