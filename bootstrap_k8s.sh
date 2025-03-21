#!/bin/bash
# bootstrap_k8s.sh: Install Docker, Kubernetes and set up node (master or worker)

# 1. Common Setup (applies to all nodes)
swapoff -a  # Disable swap (Kubernetes requires swap off)
modprobe br_netfilter || true
# Enable necessary sysctls for Kubernetes networking
echo "net.bridge.bridge-nf-call-iptables=1" > /etc/sysctl.d/90-k8s.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/90-k8s.conf
echo "net.bridge.bridge-nf-call-ip6tables=1" >> /etc/sysctl.d/90-k8s.conf
sysctl --system

# Install Docker
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg-agent gnupg software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker.io  # (Using Ubuntu's docker.io package for simplicity)
systemctl enable --now docker

# Adjust Docker cgroup driver to systemd (to match kubelet's expectations)
cat <<EOF > /etc/docker/daemon.json
{ "exec-opts": ["native.cgroupdriver=systemd"] }
EOF
systemctl restart docker

# Add Kubernetes apt repository
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg # allow unprivileged APT programs to read this keyring
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
chmod 644 /etc/apt/sources.list.d/kubernetes.list   # helps tools such as command-not-found to work correctly
apt-get update
# Install Kubernetes components
apt-get install -y kubeadm kubelet kubectl
apt-mark hold kubeadm kubelet kubectl

# 2. Node-specific setup (master vs worker)
NODE_NAME=$(hostname)
if [[ "$NODE_NAME" == "kmaster" ]]; then
  echo "[+] Initializing Kubernetes master node"
  # Initialize Kubernetes control-plane
  # Ignore SystemVerification preflight check - This is standard practice for containerized K8s environments
  # as they share the host kernel and don't need direct kernel config access. The necessary modules
  # (overlay, br_netfilter, etc.) are already loaded on the host VM.
  kubeadm init --apiserver-advertise-address=10.10.10.101 --pod-network-cidr=10.244.0.0/16 --ignore-preflight-errors=SystemVerification
  # Set up kubeconfig for convenience
  mkdir -p $HOME/.kube
  cp -f /etc/kubernetes/admin.conf $HOME/.kube/config

  # Install a CNI plugin (Flannel for networking)
  kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
  
  kubectl -n kube-system get configmap kube-proxy -o yaml | sed -e "s/maxPerCore: .*$/maxPerCore: 0/" | kubectl apply -f -
  # Generate join command script for workers
  # We need to add the --ignore-preflight-errors=SystemVerification flag to the join command
  # to allow workers to join the cluster without the kernel verification check.
  kubeadm token create --print-join-command > /pvs/joincmd.tmp
  echo "$(cat /pvs/joincmd.tmp) --ignore-preflight-errors=SystemVerification" > /pvs/joincluster.sh
  chmod +x /pvs/joincluster.sh
  echo "[+] Master initialized. Join command saved to /pvs/joincluster.sh"
  
  # Install Helm (v3) on master
  curl -fsSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

else
  # Worker node setup: join the cluster
  echo "[+] $(hostname): Waiting for join script"
  # Wait until the join script appears on the shared NFS (created by master)
  JOIN_SCRIPT="/pvs/joincluster.sh"
  RUNS=0
  while [ ! -f "$JOIN_SCRIPT" ]; do
    sleep 5
    RUNS=$((RUNS + 1))
    if [ $RUNS -gt 10 ]; then
      echo "Error: Timed out waiting for join script."
      exit 1
    fi
  done
  echo "[+] Joining worker $(hostname) to cluster"
  bash $JOIN_SCRIPT
fi
