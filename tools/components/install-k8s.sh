#!/bin/bash

set -e

KUBERNETES_VERSION="${1:-1.28}"
SYSTEMD_CGROUP="${2:-true}"

sudo rm -rf /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo rm -rf /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/deb/Release.key |
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/deb/ /" |
    sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update >/dev/null
sudo apt-get install -y kubelet kubeadm kubectl >/dev/null
sudo apt-mark hold kubelet kubeadm kubectl >/dev/null
echo "ok... kubernetes $KUBERNETES_VERSION installed"

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe -a overlay br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system >/dev/null
echo "ok... enabled ip forwarding and bridge netfilter"

# if use systemd cgroup
if [ "$SYSTEMD_CGROUP" = "true" ]; then
    sudo sed -i 's/^\([[:space:]]*SystemdCgroup = \)false/\1true/' /etc/containerd/config.toml
    sudo systemctl restart containerd >/dev/null
    echo "ok... enabled systemd cgroup for runc"
fi

export NO_PROXY="$NO_PROXY,10.0.0.0/8,192.168.0.0/16"
if ! grep -q 'export NO_PROXY=' ~/.bashrc; then
    echo "export NO_PROXY=$NO_PROXY" >>~/.bashrc
fi
echo "ok... set no_proxy for kubernetes"

sudo swapoff -a
sudo sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab
echo "ok... swap disabled"

sudo -E kubeadm init \
  --image-repository=registry.cn-hangzhou.aliyuncs.com/google_containers \
  --pod-network-cidr=192.168.0.0/16
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config \
	&& sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
echo "ok... kubernetes cluster initialized"

kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.4/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.4/manifests/custom-resources.yaml
echo "ok... calico network plugin installed"

cat > /tmp/kata-runtime.yaml <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata
handler: kata
EOF
kubectl apply -f /tmp/kata-runtime.yaml
echo "ok... kata runtime class created"

echo ""
echo "please run the following commands to complete the setup"
echo "source ~/.bashrc"
