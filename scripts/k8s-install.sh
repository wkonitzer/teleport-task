#!/usr/bin/env bash
set -euo pipefail

echo "===> Kubernetes node setup starting"

# ----------------------------
# 0. Sanity checks
# ----------------------------
if command -v snap >/dev/null 2>&1; then
  if snap list | grep -E '(kubelet|microk8s)' >/dev/null 2>&1; then
    echo "ERROR: snap kubelet or microk8s detected. Remove it first:"
    echo "  sudo snap remove kubelet --purge"
    echo "  sudo snap remove microk8s --purge"
    exit 1
  fi
fi

# ----------------------------
# 1. Kernel & sysctl requirements
# ----------------------------
echo "===> Configuring kernel modules and sysctl"

cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# ----------------------------
# 2. Install containerd
# ----------------------------
echo "===> Installing containerd"

apt-get update
apt-get install -y containerd

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

# ----------------------------
# 3. Add Kubernetes apt repository (v1.29)
# ----------------------------
echo "===> Adding Kubernetes apt repository"

apt-get install -y apt-transport-https ca-certificates curl gpg

mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" \
| tee /etc/apt/sources.list.d/kubernetes.list

apt-get update

# ----------------------------
# 4. Install kubelet + kubeadm (+ kubectl optionally)
# ----------------------------
echo "===> Installing kubelet and kubeadm"

apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet

# ----------------------------
# 5. Final checks
# ----------------------------
echo "===> Verifying installation"

kubeadm version
kubelet --version
kubectl version --client

## Fix config
sudo tee /etc/crictl.yaml >/dev/null <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo sed -i '/^KUBELET_EXTRA_ARGS=/d' /etc/default/kubelet
echo 'KUBELET_EXTRA_ARGS=--container-runtime-endpoint=unix:///run/containerd/containerd.sock' | sudo tee -a /etc/default/kubelet

sudo swapoff -a
sudo sed -i.bak 's|^/swap.img|#/swap.img|' /etc/fstab

NEW_HOST="node-$(openssl rand -hex 3)"
sudo hostnamectl set-hostname "$NEW_HOST"
sudo sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $NEW_HOST/" /etc/hosts

echo "===> Node setup complete"
echo "Please reboot"

