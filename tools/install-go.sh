#!/bin/bash

set -e

GO_VERSION="${1:-1.24.5}"

OS="$(uname | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
if [ "$ARCH" = "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    ARCH="arm64"
elif [ "$ARCH" = "s390x" ]; then
    ARCH="s390x"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

curl -Lo /tmp/go${GO_VERSION}.${OS}-${ARCH}.tar.gz \
    https://go.dev/dl/go${GO_VERSION}.${OS}-${ARCH}.tar.gz >/dev/null

sudo rm -rf /usr/local/go

sudo tar -C /usr/local -xzf "/tmp/go${GO_VERSION}.${OS}-${ARCH}.tar.gz" >/dev/null

if ! grep -q 'export PATH=$PATH:/usr/local/go/bin' ~/.bashrc; then
    echo 'export PATH=$PATH:/usr/local/go/bin' >>~/.bashrc
fi

echo "ok... go ${GO_VERSION} installed, run the following to update your PATH"
echo "source ~/.bashrc"
