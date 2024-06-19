#!/usr/bin/env bash
set -euo pipefail

METRICS_VERSION=0.7.0

IP=$(ip a | grep enp0s1 | grep inet | awk '{print $2}' | cut -d / -f 1)
#Here we create a kubeadm config rather than providing individual flags to the kubeadm init command. It is done this way because we need to add 2 kubelet settings which are needed for communication with the containerd CRI and for installing the metrics-server.
cat > kubeadm-config.yaml << EOF
# kubeadm-config.yaml
kind: ClusterConfiguration
apiVersion: kubeadm.k8s.io/v1beta3
kubernetesVersion: v1.30.2
networking:
  serviceSubnet: "10.96.0.0/16"
  podSubnet: "10.244.0.0/16"
  dnsDomain: "cluster.local"
controlPlaneEndpoint: "${IP}:6443"
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
serverTLSBootstrap: true
EOF

sudo kubeadm init --config kubeadm-config.yaml

mkdir ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
chmod 600 ~/.kube/config
sudo kubeadm token create --print-join-command | sudo tee /tmp/join-command.sh > /dev/null
sudo chmod +x /tmp/join-command.sh

echo "Installing Calico for pod networking..."

kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/tigera-operator.yaml

for s in $(seq 60 -10 10)
do
    echo "Waiting $s seconds for calico deployment pods to be running"
    sleep 10
done

kubectl apply -f /tmp/calico.yaml

echo "Installing metrics server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v${METRICS_VERSION}/components.yaml
#Approving csr requests generated after the metrics server deployment
kubectl get csr --no-headers | awk '{print $1}' | xargs -I {} kubectl certificate approve {}