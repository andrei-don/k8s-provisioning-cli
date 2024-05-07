#!/usr/bin/env bash
set -euo pipefail

CONTROLLER_NODES=$1
WORKER_NODES=$2
NODE_SUFFIX=$3

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
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

# Setting up token for all nodes, necessary for High Availability in k3s.
openssl rand -base64 16 > /tmp/token
for node in $CONTROLLER_NODES $WORKER_NODES
do
    echo "Copying provisioning scripts for k3s cluster to $node..."
    multipass transfer $SCRIPT_DIR/*.sh $node:/tmp/
    echo "Copying token for k3s cluster to $node..."
    multipass transfer /tmp/token $node:/tmp/
done

# Setting up the first controlplane node
echo "Setting up controller01-${NODE_SUFFIX}."

multipass exec controller01-${NODE_SUFFIX} -- /tmp/setup-controlplane-first.sh 
echo "The first control node finished provisioning!"


for node in controller02-${NODE_SUFFIX} controller03-${NODE_SUFFIX}
do
    echo "Setting up controlplane in $node..."
    multipass exec $node -- /tmp/setup-secondary-controlplanes.sh "$NODE_SUFFIX"
done

for node in $WORKER_NODES
do
    echo "Running the join command in $node..."
    multipass exec $node -- /tmp/setup-workers.sh "$NODE_SUFFIX"
done

for node in $CONTROLLER_NODES
do
    echo "Adding autocompletion for kubectl and its alias in $node..."
    multipass transfer $SCRIPT_DIR/../../common-tasks-controlplanes.sh $node:/tmp/
    multipass exec $node -- /tmp/common-tasks-controlplanes.sh
done

rm /tmp/token