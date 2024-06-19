#!/usr/bin/env bash
set -euo pipefail

#Install the containerd CRI version 1.7.12
CONTAINERD_VERSION=1.7.18
CRICTL_VERSION=1.30.0
#Download and unzip the app
curl -sLO https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-arm64.tar.gz
sudo tar Cxzvf /usr/local containerd-${CONTAINERD_VERSION}-linux-arm64.tar.gz >/dev/null

if [ $? -eq 0 ]; then
    echo "Copied the containerd binaries to /usr/local!"
fi

#Download the systemd unit file for containerd
curl -sLO https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
sudo mkdir -p /usr/local/lib/systemd/system/
sudo mv containerd.service /usr/local/lib/systemd/system/

# Create containerd configuration file
sudo mkdir -p /etc/containerd/
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# Enable systemd CGroup driver
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml >/dev/null

# Installing crictl
curl -sLO https://github.com/kubernetes-sigs/cri-tools/releases/download/v${CRICTL_VERSION}/crictl-v${CRICTL_VERSION}-linux-arm64.tar.gz
sudo tar zxvf crictl-v${CRICTL_VERSION}-linux-arm64.tar.gz -C /usr/local/bin >/dev/null

if [ $? -eq 0 ]; then
    echo "Copied the crictl binaries to /usr/local!"
fi

rm -f crictl-v${CRICTL_VERSION}-linux-arm64.tar.gz

# Configure crictl to work with containerd
sudo crictl config runtime-endpoint unix:///var/run/containerd/containerd.sock

# Set containerd to auto-start at boot (enable it).
sudo systemctl daemon-reload
sudo systemctl enable --now containerd

