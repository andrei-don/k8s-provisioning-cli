#!/usr/bin/env bash
set -euo pipefail

HA_PROXY_VERSION=2.9

NODE_SUFFIX=$1

sudo apt-get install --no-install-recommends software-properties-common >/dev/null 2>&1
sudo add-apt-repository ppa:vbernat/haproxy-${HA_PROXY_VERSION} -y >/dev/null 2>&1
sudo apt-get install haproxy=${HA_PROXY_VERSION}.\* -y >/dev/null 2>&1

if [ ! -f "/tmp/ip_list" ]; then
    echo "File not found: ip_list"
    exit 1
fi

IP1=$(sed -n '1p' "/tmp/ip_list")
IP2=$(sed -n '2p' "/tmp/ip_list")
IP3=$(sed -n '3p' "/tmp/ip_list")
HAPROXY_IP=$(sed -n '4p' "/tmp/ip_list")

cat > haproxy.cfg << EOF
frontend k8s-api
    bind ${HAPROXY_IP}:6443
    mode tcp
    option tcplog
    timeout client 300000
    default_backend k8s-api

backend k8s-api
    mode tcp
    option tcplog
    option tcp-check
        timeout server 300000
    balance roundrobin
    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100

        server controller01-${NODE_SUFFIX} ${IP1}:6443 check
        server controller02-${NODE_SUFFIX} ${IP2}:6443 check
        server controller03-${NODE_SUFFIX} ${IP3}:6443 check
EOF

sudo mv haproxy.cfg /etc/haproxy
sudo systemctl restart haproxy