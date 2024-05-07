#!/usr/bin/env bash
set -euo pipefail

METRICS_VERSION=0.7.0

HAPROXY_IP=$(cat /etc/hosts | grep haproxy | awk {'print $1'})
#Here we create a kubeadm config rather than providing individual flags to the kubeadm init command. It is done this way because we need to add 2 kubelet settings which are needed for communication with the containerd CRI and for installing the metrics-server.
cat > kubeadm-config.yaml << EOF
# kubeadm-config.yaml
kind: ClusterConfiguration
apiVersion: kubeadm.k8s.io/v1beta3
kubernetesVersion: v1.29.1
networking:
  serviceSubnet: "10.96.0.0/16"
  podSubnet: "10.244.0.0/16"
  dnsDomain: "cluster.local"
apiServer:
  certSANs:
  - "haproxy"
  - ${HAPROXY_IP}
controlPlaneEndpoint: "${HAPROXY_IP}:6443"
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
CERTNODEKEY=$(sudo kubeadm init phase upload-certs --upload-certs | tail -n 1)
sudo kubeadm token create --print-join-command --certificate-key "$CERTNODEKEY"| sudo tee /tmp/join-command-controller.sh > /dev/null
sudo kubeadm token create --print-join-command| sudo tee /tmp/join-command-worker.sh > /dev/null
sudo chmod +x /tmp/join-command-controller.sh
sudo chmod +x /tmp/join-command-worker.sh

echo "Installing Calico for pod networking..."

kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/tigera-operator.yaml

for s in $(seq 60 -10 10)
do
    echo "Waiting $s seconds for weavenet deployment pods to be running"
    sleep 10
done

kubectl apply -f /tmp/calico.yaml

echo "Installing metrics server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v${METRICS_VERSION}/components.yaml
#Approving csr requests generated after the metrics server deployment
kubectl get csr --no-headers | awk '{print $1}' | xargs -I {} kubectl certificate approve {}

#Pre-req to copy the kubernetes pki from the first controller node to the local machine
sudo cp -r /etc/kubernetes/pki /home/ubuntu
sudo cp /etc/kubernetes/admin.conf /home/ubuntu
sudo chmod +r /home/ubuntu/admin.conf