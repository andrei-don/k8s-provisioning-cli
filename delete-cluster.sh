#!/usr/bin/env bash

set -eo pipefail

#Storing the state of the previous cluster since we want to delete all its VMs.
touch /tmp/to-be-deleted-vms

NODES=("worker" "controller" "haproxy")
for node in ${NODES[@]}
do
    multipass list | grep $node >> /tmp/to-be-deleted-vms || true
done

OLD_VMS_NUM=$(cat /tmp/to-be-deleted-vms | wc -l)
 
if [ $OLD_VMS_NUM -gt 0 ]; then
    for i in $(seq 1 $OLD_VMS_NUM)
    do
        old_vm=$(head -n "$i" /tmp/to-be-deleted-vms | tail -n 1 | awk '{print $1}')
        echo "Deleting node $old_vm..."
        multipass delete $old_vm
    done
else
    echo "The nodes are already deleted!"
fi

multipass purge
rm /tmp/to-be-deleted-vms