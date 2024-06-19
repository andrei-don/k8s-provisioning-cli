#!/usr/bin/env bash
set -euo pipefail

NODE_SUFFIX=$1

HAPROXY_IP=$(cat /etc/hosts | grep haproxy | awk {'print $1'})
TOKEN=$(cat /tmp/token)
INSTALL_K3S_VERSION='v1.30.1+k3s1'

curl -sfL https://get.k3s.io | K3S_TOKEN=$TOKEN INSTALL_K3S_VERSION=$INSTALL_K3S_VERSION sh -s - server \
--tls-san=$HAPROXY_IP \
--server https://controller01-${NODE_SUFFIX}:6443

rm /tmp/token

# Adding the kubeconfig to the usual location so that the user does not need to use sudo with kubectl commands on the controllers
mkdir ~/.kube
sudo mv /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown ubuntu:ubuntu ~/.kube/config