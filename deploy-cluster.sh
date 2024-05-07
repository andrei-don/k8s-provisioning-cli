#!/usr/bin/env bash
set -eo pipefail

WORKER_NODES_NUM=1
CONTROL_NODES_NUM=1
MEM_GB=$(( $(sysctl hw.memsize | cut -d ' ' -f 2) /  1073741824 ))
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/scripts
VM_MEM_GB=5G
K3S=false
DUAL_MODE=false

# Checking if the user added the --worker-nodes-num and --control-node-num flag with the required value. If no value is provided a default value of 1 worker node will be used.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workers=*)
            WORKER_NODES_NUM="${1#*=}"
            shift 1
            ;;
        --controllers=*)
            CONTROL_NODES_NUM="${1#*=}"
            shift 1
            ;;
        --k3s)
            K3S=true
            shift 1
            ;;
        --dual-mode)
            DUAL_MODE=true
            shift 1
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

TOTAL_NODES=$((CONTROL_NODES_NUM + WORKER_NODES_NUM))

if [ "$TOTAL_NODES" -gt 4 ]; then
    echo "Cannot provision more than 4 cluster nodes."
    exit 1
elif [ "$CONTROL_NODES_NUM" -eq 3 ] && [ "$WORKER_NODES_NUM" -eq 0 ]; then
    echo "Invalid input, you cannot have a HA cluster with 0 workers."
    exit 1
elif [ "$CONTROL_NODES_NUM" -eq 0 ]; then
    echo "Invalid input, you need at least one control plane node."
    exit 1
elif (("$CONTROL_NODES_NUM" % 2 == 0)); then
    echo "There is no point to provision an even number of control nodes. See https://thenewstack.io/how-many-nodes-for-your-kubernetes-control-plane/#:~:text=Etcd%20uses%20a%20quorum%20system,2)."
    exit 1
else
    echo "Cluster sizing is fine."
fi

if [ $MEM_GB -le 8 ]
then
    echo  "System RAM is ${MEM_GB}GB. This is insufficient to deploy a working cluster."
    exit 1
fi

# If k3s is selected, ask the user if he is happy with the choice

if [ "$K3S" = true ]; then
    read -p "You selected a cluster with the k3s distribution. Do you want to proceed with this lighter setup rather than k8s (y/n)? " ans
    [ "$ans" != 'y' ] && K3S=false && echo 'Provisioning a k8s cluster instead...'
fi

# If the nodes are running and the --dual-mode flag is not set, reset them

if [ "$DUAL_MODE" = true ]; then
    CLUSTER_TYPE="-secondary"
else
    CLUSTER_TYPE=""
fi

IS_DUAL_MODE=$(multipass list --format json | jq -r '.list[].name' | grep -q "-secondary"; echo $?)
#The below is needed because the egrep fails and returns nothing if no previous cluster was deployed. The TOTAL_NODES_PRE_DEPLOYMENT variable will however return the expected value.
set +e
TOTAL_NODES_PRE_DEPLOYMENT=$(multipass list | egrep '(controller|worker)' | wc -l)
TOTAL_NODES_POST_DEPLOYMENT=$((TOTAL_NODES + TOTAL_NODES_PRE_DEPLOYMENT))
set -e

if [ "$DUAL_MODE" = true ]  && [ "$IS_DUAL_MODE" = 0 ]; then
    read -p "The cli was already run with the dual-mode flag enabled. You can only run it once sequentially. Select 'y' if you want this script to automatically delete your clusters. Otherwise delete the clusters separately and attempt a new deployment. (y/n)?" ans
    [ "$ans" != 'y' ] && exit 1
    ./delete-cluster.sh
    exit 0
elif [ "$TOTAL_NODES_POST_DEPLOYMENT" -gt 4 ] && ([ "$IS_DUAL_MODE" = 0 ] || [ "$DUAL_MODE" = true ]); then
    read -p "The total number of combined cluster nodes is too big! Delete the existing clusters (y/n)?" ans
    [ "$ans" != 'y' ] && exit 1
    ./delete-cluster.sh
    exit 0
elif [ "$TOTAL_NODES" -gt 2 ] && ([ "$DUAL_MODE" = true ] || [ "$IS_DUAL_MODE" = 0 ]); then
    echo "Too many nodes for dual mode. Cannot have more than 1 worker/controller node due to localhost performance limits."
    exit 1
elif [ "$TOTAL_NODES" -le 2 ] && ([ "$DUAL_MODE" = true ] || [ "$IS_DUAL_MODE" = 0 ]); then
    echo "Deploying a secondary cluster in dual mode!"
else
    if multipass list --format json | jq -r '.list[].name' | egrep '(controller01|controller02|controller03|worker01|worker02|worker03)-node' > /dev/null
    then
        read -p "VMs are running. You need to delete your current cluster before provisioning a new one. Delete and rebuild them (y/n)? " ans
        [ "$ans" != 'y' ] && exit 1
        ./delete-cluster.sh
    fi
fi


if [ "$CONTROL_NODES_NUM" -eq 3 ]; then
    HA_CLUSTER=true
else
    HA_CLUSTER=false
fi

if [ "$K3S" = true ]; then
    CLUSTER_DISTRO="k3s"
else
    CLUSTER_DISTRO="k8s"
fi

NODE_SUFFIX="node-${CLUSTER_DISTRO}${CLUSTER_TYPE}"

CONTROLLER_NODES=$(for n in $(seq 1 $CONTROL_NODES_NUM) ; do echo -n "controller0${n}-${NODE_SUFFIX} " ; done)
WORKER_NODES=()
if [ "$WORKER_NODES_NUM" -gt 0 ]; then
    WORKER_NODES=$(for n in $(seq 1 $WORKER_NODES_NUM) ; do echo -n "worker0${n}-${NODE_SUFFIX} " ; done)
fi

for node in $CONTROLLER_NODES $WORKER_NODES
do
    echo "Launching node $node"
    multipass launch --disk 50G --memory $VM_MEM_GB --cpus 2 --name $node jammy
    echo "Node booted!"
done

echo "Provisioning a ${CLUSTER_DISTRO} cluster..."

if [ "$HA_CLUSTER" = true ]; then
    SCRIPT_PATH="$SCRIPT_DIR/high-availability-controlplane/$CLUSTER_DISTRO/setup-HA-controlplane.sh"
else
    SCRIPT_PATH="$SCRIPT_DIR/single-node-controlplane/$CLUSTER_DISTRO/setup-single-controlplane.sh"
fi

"$SCRIPT_PATH" "$CONTROLLER_NODES" "$WORKER_NODES" "$NODE_SUFFIX"

#Checking if the user wants the Kubernetes dashboard installed on the cluster, together with the local-admin service account with cluster-admin cluserrole:
read -p "The script is about to install the kubernetes-dashboard manifest in your cluster. It will also create a local-admin service account with cluster admin rights to log into the dashboard. If you do not want to deploy the kubernetes-dashboard GUI, please do not proceed. Do you want to proceed (y/n)? " ans
if [ "$ans" != 'y' ]; then
    echo "Skipping kubernetes-dashboard deployment..."
else
    multipass transfer "${SCRIPT_DIR}/deploy-kubernetes-dashboard.sh" controller01-${NODE_SUFFIX}:/tmp/deploy-kubernetes-dashboard.sh
    multipass exec controller01-${NODE_SUFFIX} -- /tmp/deploy-kubernetes-dashboard.sh
fi
    
#Checking if this is an HA cluster by listing all VMs. If it is one, then the IP of haproxy load balancer will be assigned, otherwise the ip of controller01-node will be used
IS_HAPROXY=$(multipass list --format json | jq -r '.list[].name' | grep -q "haproxy"; echo $?)

#Creating kubeconfig on localhost so that we can connect to the cluster from our local.
read -p "The script is about to replace the contents of your ~/.kube/config file. If you have other entries from other clusters that you still want to connect to, please do not proceed. Do you want to proceed (y/n)? " ans
if [ "$ans" != 'y' ]; then
    echo "CLUSTER PROVISIONED SUCCESSFULLY!"
    curl parrot.live &
    sleep 3
    kill $(pgrep curl)
    exit 0
else
    openssl genrsa -out /tmp/local-admin.key 2048
    openssl req -new -key /tmp/local-admin.key -subj "/CN=local-admin/" -out /tmp/local-admin.csr
    multipass transfer /tmp/local-admin.csr controller01-${NODE_SUFFIX}:/tmp/
    multipass transfer /tmp/local-admin.key controller01-${NODE_SUFFIX}:/tmp/
    rm /tmp/local-admin*
    multipass transfer $SCRIPT_DIR/approving-local-admin-csr.sh controller01-${NODE_SUFFIX}:/tmp/
    multipass exec controller01-${NODE_SUFFIX} -- /tmp/approving-local-admin-csr.sh $IS_HAPROXY
    if [ ! -d ~/.kube/ ]; then
        echo "The .kube directory and the kubeconfig file will be created locally"
        mkdir ~/.kube/
        multipass transfer controller01-${NODE_SUFFIX}:/tmp/config ~/.kube/
    elif [ ! -f ~/.kube/config ]; then
        echo "The kubeconfig file will be created locally"
        multipass transfer controller01-${NODE_SUFFIX}:/tmp/config ~/.kube/
    else
        echo "The kubeconfig file exists, replacing contents..."
        truncate -s 0 ~/.kube/config
        multipass transfer controller01-${NODE_SUFFIX}:/tmp/config ~/.kube/
    fi
    chmod 600 ~/.kube/config
    multipass exec controller01-${NODE_SUFFIX} -- rm -rf /tmp/local-*
    multipass exec controller01-${NODE_SUFFIX} -- rm -rf /tmp/config
fi

echo "CLUSTER PROVISIONED SUCCESSFULLY!"
curl parrot.live &
sleep 3
kill $(pgrep curl)