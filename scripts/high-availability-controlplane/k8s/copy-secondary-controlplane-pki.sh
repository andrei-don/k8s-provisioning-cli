#!/usr/bin/env bash

set -euo pipefail


#Copying the pki infra needed for the other controller nodes
sudo mkdir /etc/kubernetes/pki/
sudo mkdir /etc/kubernetes/pki/etcd

sudo mv /home/ubuntu/ca.crt /etc/kubernetes/pki
sudo mv /home/ubuntu/ca.key /etc/kubernetes/pki
sudo mv /home/ubuntu/sa.pub /etc/kubernetes/pki
sudo mv /home/ubuntu/sa.key /etc/kubernetes/pki
sudo mv /home/ubuntu/front-proxy-ca.crt /etc/kubernetes/pki
sudo mv /home/ubuntu/front-proxy-ca.key /etc/kubernetes/pki
sudo mv /home/ubuntu/etcd/ca.crt /etc/kubernetes/pki/etcd
sudo mv /home/ubuntu/etcd/ca.key /etc/kubernetes/pki/etcd
sudo mv /home/ubuntu/admin.conf /etc/kubernetes/