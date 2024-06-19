#!/usr/bin/env bash
set -euo pipefail

NODE_SUFFIX=$1

TOKEN=$(cat /tmp/token)
INSTALL_K3S_VERSION='v1.30.1+k3s1'

curl -sfL https://get.k3s.io | K3S_TOKEN=$TOKEN INSTALL_K3S_VERSION=$INSTALL_K3S_VERSION sh -s - agent \
--server https://controller01-${NODE_SUFFIX}:6443

rm /tmp/token