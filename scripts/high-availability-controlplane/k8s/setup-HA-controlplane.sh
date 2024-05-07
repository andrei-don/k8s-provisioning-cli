#!/usr/bin/env bash
set -euo pipefail

CONTROLLER_NODES=$1
WORKER_NODES=$2
NODE_SUFFIX=$3

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
MANIFEST_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/../../../manifests


multipass launch --disk 10G --memory 500M --cpus 1 --name haproxy jammy

#Installing HAProxy from PPA.
multipass transfer $SCRIPT_DIR/../setup-haproxy.sh haproxy:/tmp/

for node in controller01-${NODE_SUFFIX} controller02-${NODE_SUFFIX} controller03-${NODE_SUFFIX} haproxy
do
  echo $(multipass info $node --format json | jq -r 'first( .info[] | .ipv4[0] )') >> /tmp/ip_list
done
multipass transfer /tmp/ip_list $node:/tmp/
rm /tmp/ip_list
multipass exec haproxy -- /tmp/setup-haproxy.sh "$NODE_SUFFIX"
echo "Deployed HAProxy!"

#Add entries in the host file

echo "Setting host files on nodes"
HOSTENTRIES=/tmp/hostentries
[ -f $HOSTENTRIES ] && rm -f $HOSTENTRIES
for node in $CONTROLLER_NODES $WORKER_NODES haproxy
do
    echo "Adding $node to the host entries..."
    ip=$(multipass info $node --format json | jq -r 'first( .info[] | .ipv4[0] )') > /dev/null
    echo "$ip $node" >> $HOSTENTRIES
done

# Adding the host entries to the /etc/hosts location on all the cluster nodes
for node in $CONTROLLER_NODES $WORKER_NODES haproxy
do
    echo "Editing the /etc/hosts file for node $node..."
    multipass transfer $HOSTENTRIES $node:/tmp/ 
    multipass transfer $SCRIPT_DIR/../../setup-host-files.sh $node:/tmp/
    multipass exec $node -- /tmp/setup-host-files.sh
    echo "Host entries added for $node !"
done

# Setting up common components for the worker and controlplane nodes

for node in $CONTROLLER_NODES $WORKER_NODES
do
    echo "Setting up common components in $node..."
    multipass transfer $SCRIPT_DIR/../../*.sh $node:/tmp/
    multipass transfer $SCRIPT_DIR/*.sh $node:/tmp/

    for script in setup-kernel.sh setup-cri.sh kube-components.sh
    do
        echo "Executing $script on $node..........................................................................."
        multipass exec $node -- /tmp/$script 
    done
done

# Setting up the first controlplane node
echo "Setting up controller01-node."
multipass transfer $MANIFEST_DIR/calico.yaml controller01-${NODE_SUFFIX}:/tmp/
multipass exec controller01-${NODE_SUFFIX} -- /tmp/setup-controlplane-first.sh 
multipass transfer controller01-${NODE_SUFFIX}:/tmp/join-command-controller.sh /tmp/
multipass transfer controller01-${NODE_SUFFIX}:/tmp/join-command-worker.sh /tmp/
set +e
multipass transfer --recursive controller01-${NODE_SUFFIX}:/home/ubuntu/pki /tmp 2>/dev/null
multipass transfer controller01-${NODE_SUFFIX}:/home/ubuntu/admin.conf /tmp 2>/dev/null
set -e
echo "The first control node finished provisioning!"


for node in controller02-${NODE_SUFFIX} controller03-${NODE_SUFFIX}
do
    echo "Setting up controlplane in $node..."
    multipass transfer $MANIFEST_DIR/calico.yaml $node:/tmp/
    set +e
    multipass transfer /tmp/admin.conf $node:/home/ubuntu 2>/dev/null
    multipass transfer /tmp/pki/ca.crt $node:/home/ubuntu 2>/dev/null
    multipass transfer /tmp/pki/ca.key $node:/home/ubuntu 2>/dev/null
    multipass transfer /tmp/pki/sa.pub $node:/home/ubuntu 2>/dev/null
    multipass transfer /tmp/pki/sa.key $node:/home/ubuntu 2>/dev/null
    multipass transfer /tmp/pki/front-proxy-ca.crt $node:/home/ubuntu 2>/dev/null
    multipass transfer /tmp/pki/front-proxy-ca.key $node:/home/ubuntu 2>/dev/null
    multipass exec $node -- sudo mkdir /home/ubuntu/etcd
    multipass exec $node -- sudo chown -R ubuntu:ubuntu /home/ubuntu/etcd
    multipass transfer /tmp/pki/etcd/ca.crt $node:/home/ubuntu/etcd 2>/dev/null
    multipass transfer /tmp/pki/etcd/ca.key $node:/home/ubuntu/etcd 2>/dev/null
    multipass transfer /tmp/join-command-controller.sh $node:/tmp/
    set -e
    multipass exec $node -- /tmp/copy-secondary-controlplane-pki.sh
    multipass exec $node -- sudo /tmp/join-command-controller.sh
    multipass exec $node -- /tmp/setup-secondary-controlplanes.sh
done

rm /tmp/admin.conf
rm -rf /tmp/pki
rm /tmp/join-command-controller.sh

for node in $WORKER_NODES
do
    echo "Running the join command in $node..."
    multipass transfer /tmp/join-command-worker.sh $node:/tmp/
    multipass exec $node -- sudo /tmp/join-command-worker.sh
done

# This step is needed to approve the CSRs for the kubelets, see https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/#:~:text=One%20known%20limitation%20is%20that%20the%20CSRs%20(Certificate%20Signing%20Requests)%20for%20these%20certificates%20cannot%20be%20automatically%20approved%20by%20the%20default%20signer%20in%20the%20kube%2Dcontroller%2Dmanager%20%2D%20kubernetes.io/kubelet%2Dserving.%20This%20will%20require%20action%20from%20the%20user%20or%20a%20third%20party%20controller.
for node in $CONTROLLER_NODES
do
    echo "Approving the worker nodes CSRs in $node..."
    multipass exec $node -- /tmp/approve-worker-csr.sh
    echo "Adding autocompletion for kubectl and its alias in $node..."
    multipass exec $node -- /tmp/common-tasks-controlplanes.sh
done

rm /tmp/join-command-worker.sh