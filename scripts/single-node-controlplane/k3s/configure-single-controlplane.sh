#!/usr/bin/env bash
set -euo pipefail
INSTALL_K3S_VERSION='v1.29.1+k3s2'
IP=$(ip a | grep enp0s1 | grep inet | awk '{print $2}' | cut -d / -f 1)
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$INSTALL_K3S_VERSION sh -
mkdir ~/.kube
sudo mv /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown ubuntu:ubuntu ~/.kube/config

K3S_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)

cat > /tmp/join-command.sh << EOF
curl -sfL https://get.k3s.io | K3S_URL=https://${IP}:6443 K3S_TOKEN=$K3S_TOKEN  INSTALL_K3S_VERSION=$INSTALL_K3S_VERSION sh -
EOF

sudo chmod +x /tmp/join-command.sh