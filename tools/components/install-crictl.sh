#!/bin/bash

CRICTL_VERSION="${1:-v1.29.0}"

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

sudo rm -rf /usr/local/bin/crictl
sudo rm -rf /tmp/crictl-$CRICTL_VERSION-linux-$ARCH.tar.gz
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRICTL_VERSION/crictl-$CRICTL_VERSION-linux-$ARCH.tar.gz \
    -O /tmp/crictl-$CRICTL_VERSION-linux-$ARCH.tar.gz >/dev/null
sudo tar -xvf /tmp/crictl-$CRICTL_VERSION-linux-$ARCH.tar.gz -C /usr/local/bin >/dev/null

sudo bash -c "cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 100
debug: false
EOF"

echo "ok... crictl $CRICTL_VERSION installed"
