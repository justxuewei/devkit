#!/bin/bash

CUR_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

set -euo pipefail

IMAGE_NAME="niuxuewei/myubuntu-pub"
TAG="latest"
FULL_IMAGE="${IMAGE_NAME}:${TAG}"

echo "==> Building image: ${FULL_IMAGE}"
sudo docker build -t "${FULL_IMAGE}" "${CUR_PATH}"

echo "==> Logging in to Docker Hub"
sudo docker login

echo "==> Pushing image: ${FULL_IMAGE}"
sudo docker push "${FULL_IMAGE}"

echo "==> Done: ${FULL_IMAGE}"
