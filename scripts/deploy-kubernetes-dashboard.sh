#!/usr/bin/env bash
set -eo pipefail

kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

for s in $(seq 30 -10 10)
do
    echo "Waiting $s seconds for kubernetes-dashboard deployment pods to be running"
    sleep 10
done

#Creating a local admin user with full cluster admin access, to be used for authentication against the kubernetes dashboard.

kubectl create sa local-admin --namespace kubernetes-dashboard
kubectl create clusterrolebinding local-admin-dashboard --clusterrole=cluster-admin --serviceaccount=kubernetes-dashboard:local-admin

#Creating a permanent token for the local-admin service account which will serve as authentication method against the kubernetes-dashboard. This is acceptable given that we create a local k8s dev environment. For production environments short lived token should be used.

cat > local-admin-dashboard-token-secret.yaml << EOF
apiVersion: v1
kind: Secret
type: kubernetes.io/service-account-token
metadata:
  name: local-admin-token
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/service-account.name: local-admin
EOF

kubectl apply -f local-admin-dashboard-token-secret.yaml

