#!/usr/bin/env bash
set -eo pipefail

IS_HAPROXY=$1
#Getting the ip address of the apiserver. There are 2 cases here, the ip address of HAProxy in HA mode or ip of controller01-node in single controlplane mode.

IP=$(ip a | grep enp0s1 | grep inet | awk '{print $2}' | cut -d / -f 1)
if [ "$IS_HAPROXY" = 0 ]; then
    IP=$(cat /etc/hosts | grep haproxy | awk '{print $1}')
fi

#Encoding the csr, adding it in the csr manifest in the next step.
ENC_CSR=$(cat /tmp/local-admin.csr | openssl enc -base64 -A)


cat > csr.yaml <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: local-admin
spec:
  request: $ENC_CSR
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400  # one day
  usages:
  - client auth
EOF

kubectl apply -f csr.yaml
kubectl certificate approve local-admin
kubectl create clusterrolebinding local-admin --clusterrole=cluster-admin --user=local-admin

LOCAL_ADMIN_CRT=$(kubectl get csr local-admin -o=jsonpath={'.status.certificate'})
CLUSTER_CA_CRT=$(kubectl config view --raw -o=jsonpath={'.clusters[*].cluster.certificate-authority-data'})
LOCAL_ADMIN_KEY=$(cat /tmp/local-admin.key | openssl enc -base64 -A)

cat > /tmp/config << EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ${CLUSTER_CA_CRT}
    server: https://${IP}:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: local-admin
  name: local-admin@kubernetes
current-context: local-admin@kubernetes
kind: Config
preferences: {}
users:
- name: local-admin
  user:
    client-certificate-data: ${LOCAL_ADMIN_CRT}
    client-key-data: ${LOCAL_ADMIN_KEY}
EOF
