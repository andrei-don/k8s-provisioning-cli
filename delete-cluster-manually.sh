#!/usr/bin/env bash

set -eo pipefail

./delete-cluster.sh

read -p "Removing the contents of the dhcpd_leases file... DO NOT PROCEED if you have other VMs running on your local apart from the kubernetes ones! (y/n)? " ans
[ "$ans" != 'y' ] && exit 1
sudo truncate -s 0 /var/db/dhcpd_leases