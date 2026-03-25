#!/bin/bash

#!/bin/bash

set -euo pipefail

IMAGE_NAME="myubuntu"
REGISTRY="xavierniu"
TAG="latest"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"

echo "==> Building image: ${FULL_IMAGE}"
sudo docker build -t "${FULL_IMAGE}" .

echo "==> Logging in to Docker Hub"
sudo docker login -u ${REGISTRY}

echo "==> Pushing image: ${FULL_IMAGE}"
sudo docker push "${FULL_IMAGE}"

echo "==> Done: ${FULL_IMAGE}"
