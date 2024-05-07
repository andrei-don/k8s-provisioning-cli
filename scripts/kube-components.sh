#!/usr/bin/env bash
set -euo pipefail

#Install kubeadm, kubelet and kubectl
KUBE_VERSION=1.29.1

echo "Installing the runc and kubernetes apt packages."
sudo apt-get update >/dev/null 2>&1
sudo apt-get install -y apt-transport-https ca-certificates curl gpg >/dev/null 2>&1

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update >/dev/null 2>&1
sudo apt-get install -y kubelet=${KUBE_VERSION}-1.1 kubectl=${KUBE_VERSION}-1.1 kubeadm=${KUBE_VERSION}-1.1 runc >/dev/null 2>&1
sudo apt-mark hold kubelet kubeadm kubectl