#!/bin/bash

set -e

CONTAINERD_VERSION="${1:-1.7.24}"

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

sudo rm -rf /tmp/containerd-$CONTAINERD_VERSION-linux-$ARCH.tar.gz
sudo rm -rf /usr/local/bin/containerd
sudo rm -rf /usr/local/bin/ctr
sudo rm -rf /usr/local/bin/containerd-shim
sudo rm -rf /usr/local/bin/containerd-shim-runc-v1
sudo rm -rf /usr/local/bin/containerd-stress
sudo rm -rf /usr/local/bin/containerd-shim-runc-v2

wget https://github.com/containerd/containerd/releases/download/v$CONTAINERD_VERSION/containerd-$CONTAINERD_VERSION-linux-$ARCH.tar.gz \
    -O /tmp/containerd-$CONTAINERD_VERSION-linux-$ARCH.tar.gz >/dev/null
sudo tar -xvf /tmp/containerd-$CONTAINERD_VERSION-linux-$ARCH.tar.gz -C /usr/local >/dev/null

sudo rm -rf /lib/systemd/system/containerd.service
sudo sh -c "wget -qO - https://raw.githubusercontent.com/containerd/containerd/main/containerd.service > /lib/systemd/system/containerd.service"

if ! curl -Is https://x.com >/dev/null 2>&1; then
    PROXY=1
else
    PROXY=0
    echo "skip... set proxy for containerd"
fi

if [ $PROXY -eq 1 ]; then
    sed -i '/^\[Service\]/a Environment="HTTP_PROXY=http://127.0.0.1:7890"\nEnvironment="HTTPS_PROXY=http://127.0.0.1:7890"\nEnvironment="NO_PROXY=$NO_PROXY,10.0.0.0/8,192.168.0.0/16"\n' /lib/systemd/system/containerd.service
    echo "ok... set proxy for containerd"
fi

sudo systemctl daemon-reload
sudo systemctl enable --now containerd

echo "ok... containerd $CONTAINERD_VERSION installed"

sudo apt-get update >/dev/null
sudo apt-get install -y runc >/dev/null
echo "ok... runc installed"

sudo mkdir -p /etc/containerd
sudo sh -c "containerd config default > /etc/containerd/config.toml"

sudo sed -i '/^[[:space:]]*\[plugins\."io\.containerd\.grpc\.v1\.cri"\.containerd\.runtimes\]/a\
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata]\
          runtime_type = "io.containerd.kata.v2"\
          pod_annotations = ["io.katacontainers.*"]\
          privileged_without_host_devices = true\
          privileged_without_host_devices_all_devices_allowed = true\
' /etc/containerd/config.toml
sudo sed -i 's/^\([[:space:]]*level = \).*/\1"debug"/' /etc/containerd/config.toml
sudo systemctl restart containerd
echo "ok... kata runtime added to containerd"