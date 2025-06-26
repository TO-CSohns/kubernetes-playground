#!/bin/bash
set -e

### 1. Disable Swap (required by Kubernetes)
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

### 2. Load Kernel Modules
modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system

### 3. Install containerd
apt update && apt install -y containerd

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml

# Use systemd as the cgroup driver (recommended by Kubernetes)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

### 4. Add Kubernetes APT Repo
apt update && apt install -y apt-transport-https ca-certificates curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/kubernetes.gpg

echo "deb [signed-by=/etc/apt/trusted.gpg.d/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

apt update
apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

### 5. Initialize the Cluster (optional for control-plane node)
# Replace 192.168.0.10 with this node's IP
kubeadm init --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address=192.168.0.10

### 6. Set up kubectl for your user (optional)
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

### 7. Install CNI (e.g., Calico)
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

echo "✅ Kubernetes base setup is complete. Ready for kubeadm init or join."
