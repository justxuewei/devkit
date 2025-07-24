#!/bin/bash

set -e

KATA_VERSION="${1:-3.19.1}"
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

USER=$(id -un)
GROUP=$(id -gn)

sudo rm -rf /tmp/kata-static-${KATA_VERSION}-${ARCH}.tar.xz
sudo rm -rf /opt/kata
sudo rm -rf /usr/local/bin/containerd-shim-kata-v2
wget https://github.com/kata-containers/kata-containers/releases/download/${KATA_VERSION}/kata-static-${KATA_VERSION}-${ARCH}.tar.xz \
    -O /tmp/kata-static-${KATA_VERSION}-${ARCH}.tar.xz >/dev/null
sudo tar -C / -xf /tmp/kata-static-${KATA_VERSION}-${ARCH}.tar.xz
sudo chown -R ${USER}:${GROUP} /opt/kata
sudo cp /opt/kata/runtime-rs/bin/containerd-shim-kata-v2 /usr/local/bin
echo "ok... runtime-rs ${KATA_VERSION} installed"

sudo mkdir -p /etc/kata-containers/runtime-rs
sudo cp /opt/kata/share/defaults/kata-containers/runtime-rs/* /etc/kata-containers/runtime-rs/
sudo ln -fs /etc/kata-containers/runtime-rs/configuration-qemu-runtime-rs.toml /etc/kata-containers/runtime-rs/configuration.toml
sudo chown -R ${USER}:${GROUP} /etc/kata-containers
echo "ok... applied runtime-rs qemu config"
