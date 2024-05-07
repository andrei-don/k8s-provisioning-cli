#!/usr/bin/env bash
set -eo pipefail

CONTROLLER_NODES=$1
WORKER_NODES=$2

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
MANIFEST_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/../../../manifests

#Add entries in the host file

echo "Setting host files on nodes"
HOSTENTRIES=/tmp/hostentries
[ -f $HOSTENTRIES ] && rm -f $HOSTENTRIES


for node in $CONTROLLER_NODES $WORKER_NODES
do
    echo "Adding $node to the host entries..."
    ip=$(multipass info $node --format json | jq -r 'first( .info[] | .ipv4[0] )') > /dev/null
    echo "$ip $node" >> $HOSTENTRIES
done

# Adding the host entries to the /etc/hosts location on all the cluster nodes
for node in $CONTROLLER_NODES $WORKER_NODES
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

    for script in setup-kernel.sh setup-cri.sh kube-components.sh
    do
        echo "Executing $script ............"
        multipass exec $node -- /tmp/$script
    done
done

# Setting up controlplane nodes

for node in $CONTROLLER_NODES
do
    echo "Setting up controlplane in $node..."
    multipass transfer $MANIFEST_DIR/calico.yaml $node:/tmp/
    multipass transfer $SCRIPT_DIR/configure-single-controlplane.sh $node:/tmp/
    multipass exec $node -- /tmp/configure-single-controlplane.sh
    multipass transfer $node:/tmp/join-command.sh /tmp/join-command.sh
done

for node in $WORKER_NODES
do
    echo "Running the join command in $node..."
    multipass transfer /tmp/join-command.sh $node:/tmp/
    multipass exec $node -- chmod +x '/tmp/join-command.sh'
    multipass exec $node -- sudo /tmp/join-command.sh
done

# This step is needed to approve the CSRs for the kubelets, see https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/#:~:text=One%20known%20limitation%20is%20that%20the%20CSRs%20(Certificate%20Signing%20Requests)%20for%20these%20certificates%20cannot%20be%20automatically%20approved%20by%20the%20default%20signer%20in%20the%20kube%2Dcontroller%2Dmanager%20%2D%20kubernetes.io/kubelet%2Dserving.%20This%20will%20require%20action%20from%20the%20user%20or%20a%20third%20party%20controller.
for node in $CONTROLLER_NODES
do
    echo "Approving the worker nodes CSRs in $node..."
    multipass exec $node -- /tmp/approve-worker-csr.sh
    echo "Adding autocompletion for kubectl and its alias in $node..."
    multipass exec $node -- /tmp/common-tasks-controlplanes.sh
done

rm /tmp/join-command.sh
