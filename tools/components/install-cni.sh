#!/bin/bash

CNI_VERSION="${1:-v1.3.0}"

pushd /tmp

git clone --branch $CNI_VERSION \
    https://github.com/containernetworking/plugins.git \
    cni-plugins >/dev/null
pushd /tmp/cni-plugins
./build_linux.sh >/dev/null
sudo mkdir -p /opt/cni/bin
sudo cp bin/* /opt/cni/bin

echo "ok... cni-plugins installed"

sudo mkdir -p /etc/cni/net.d
sudo sh -c 'cat > /etc/cni/net.d/10-mynet.conf <<EOF
{
  "cniVersion": "0.2.0",
  "name": "mynet",
  "type": "bridge",
  "bridge": "cni0",
  "isGateway": true,
  "ipMasq": true,
  "ipam": {
    "type": "host-local",
    "subnet": "172.19.0.0/24",
    "routes": [
      { "dst": "0.0.0.0/0" }
    ]
  }
}
EOF'
echo "ok... cni config created"
