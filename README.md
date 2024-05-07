# k8s-setup
This repository hosts the code to deploy both a k8s and a k3s cluster on Apple silicon.

It can provision a k8s cluster using the kubeadm binary on VMs deployed with multipass. It also can provision a k3s cluster (a lighter Kubernetes distro, check https://docs.k3s.io/quick-start). Unfortunately machines with Apple silicon are not compatible with popular virtualization systems like Virtualbox (or most of the Vagrant providers), therefore making it impossible to create a deployment with Vagrant. 

The naming convention is "${NODE_ID}-node-${CLUSTER_DISTRO}${CLUSTER_TYPE}", where:

1. NODE_ID is controller/worker01, controller/worker02, etc.
2. CLUSTER_DISTRO is k3s or k8s.
3. CLUSTER_TYPE is "secondary", this gets appended to the node name if it is run in the *dual-mode* configuration (more on this in the sections below).

## Pre-requisites

You need to have Multipass installed on your laptop. It is a virtualization tool which makes it easy to deploy VMs on all OS types (developed by Canonical, therefore only Ubuntu is available with Multipass). Download it from https://multipass.run/install.

Kubernetes recommands minimum 2GB RAM/ 2 CPU for each node. Depending on your hardware, we can deploy maximum a 4 node cluster (we assumed a cpu of 10 cores, leaving 2 cores for the host os to run on). We can deploy 2 configurations with 4 nodes:
1. Single control node and 1-3 worker nodes.
2. HA control plane with 3 control nodes and 1 worker node (and an additional tiny VM which serves as HAProxy load balancer).

If you plan to interact with the cluster directly from localhost (without establishing a ssh session with a controller node), you need to install kubectl on your machine. The script was configured to create a local-admin user with full admin access to the cluster and write the necessary kubeconfig file inside ~/.kube/config in your localhost. With kubectl installed you can interact with your cluster straightaway! 

## How to use
1. Clone this repository
2. Go to the repo directory and make the *deploy-cluster.sh* script executable
3. run the *deploy-cluster.sh* script with any of the below flags:


    a. *--workers* for the number of worker nodes (default value is 1)

    b. *--controllers* for the number of controller nodes (default value is 1)

    c. *--k3s* if you want the k3s distro (if you omit it a k8s cluster will be provisioned instead)

    d. *--dual-mode* if you want to run a second cluster in parallel with the existing one (useful for testing automated multi-cluster deployments). This tool only accepts 2 node clusters (controller+worker) to be run in *dual-mode*. A limitation of this feature is that you can only run it once sequentially. If you plan to deploy a new secondary cluster, you need to redeploy the first cluster as well.


You can run a single control node cluster or you can run 3 control plane nodes in a high availability mode.
The total number of nodes accepted for this deployment is 4 (assumed a 10 core cpu on a mac, leaving you with 2 cores to run other tasks). Therefore any number between 1 and 3 are accepted for the worker nodes.

Each node will be provisioned with 10GB Disk, 2GB RAM and 2CPU.

The only limitation for this tool is your local machine performance. In theory you can deploy any number of worker nodes and odd number of control nodes. It has not been thoroughly tested to see its limits, however a 4 node cluster should work fine on a 10cpu core Mac.

## Quick start

Clone this repository and navigate inside the repo directory. Run the command below:
```
$ ./deploy-cluster.sh --workers=3
```
The default value for both the *--workers* and *--controllers* is 1, therefore the above command will provision a 1 controller, 3 workers k8s cluster using Multipass (the underlying hypervisor is QEMU).

In order to list all of them run the command below(that's how the output looks like for a 3 worker node cluster):
```
$ multipass list
Name                    State             IPv4             Image
controller01-node-k8s   Running           192.168.64.12    Ubuntu 22.04 LTS
                                          10.42.0.0
worker01-node-k8s       Running           192.168.64.13    Ubuntu 22.04 LTS
                                          10.42.1.0
worker02-node-k8s       Running           192.168.64.14    Ubuntu 22.04 LTS
                                          10.42.2.0
worker03-node-k8s       Running           192.168.64.15    Ubuntu 22.04 LTS
                                          10.42.3.0
```
This script also supports running different cluster configurations sequentially. Let's say you want a HA k3s cluster after you are done testing with the previous 3-worker k8s cluster. You simply run the command bellow:

```
$ ./deploy-cluster.sh --controllers=3 --k3s

Cluster sizing is fine.
You selected a cluster with the k3s distribution. Do you want to proceed with this lighter setup rather than k8s (y/n)? y
VMs are running. You need to delete your current cluster before provisioning a new one. Delete and rebuild them (y/n)? y
```

After you agree to delete existing VMs, the script will delete and provision a new cluster according to your spec (a 3 controller node HA k3s cluster in this case). You can now interact with the cluster from your local, if you installed kubectl try the command below:

```
$ kubectl top nodes
NAME                    CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%   
controller01-node-k3s   26m          1%     979Mi           49%       
controller02-node-k3s   16m          0%     629Mi           32%       
controller03-node-k3s   18m          0%     619Mi           31%       
worker01-node-k3s       5m           0%     343Mi           17% 
```

You can also use the *dual-mode* feature. You can have 2 simultaneous 2 node clusters (1 worker + 1 controller). Start with provisioning a 2 node cluster of your choice:
```
$ ./deploy-cluster.sh
```
After that run a new command with the *--dual-mode* flag:

```
$ ./deploy-cluster.sh --k3s --dual-mode
Cluster sizing is fine.
You selected a cluster with the k3s distribution. Do you want to proceed with this lighter setup rather than k8s (y/n)? y
Deploying a secondary cluster in dual mode!
```

When listing the nodes you can see you have 2 different clusters now:
```
$ multipass list
Name                             State             IPv4             Image
controller01-node-k3s-secondary  Running           192.168.64.19    Ubuntu 22.04 LTS
                                                   10.42.0.0
                                                   10.42.0.1
controller01-node-k8s            Running           192.168.64.17    Ubuntu 22.04 LTS
                                                   10.244.0.1
worker01-node-k3s-secondary      Running           192.168.64.20    Ubuntu 22.04 LTS
                                                   10.42.1.0
worker01-node-k8s                Running           192.168.64.18    Ubuntu 22.04 LTS
                                                   10.244.192.0
```
Feel free to use this feature to test multi cluster deployments.

You can use kubectl directly from your localhost if you have it installed. If that is not the case, you will run the admin tasks and kubectl commands from one of the controler nodes, you can ssh into it through Multipass:
```
multipass shell controller01-node-k8s
```
The cluster comes provisioned with the *metrics-server*, you can run the kubectl top commands to find the resource consumption:

```
$ kubectl top pods
NAME                                        CPU(cores)   MEMORY(bytes)   
coredns-76f75df574-gczvd                        2m           49Mi            
coredns-76f75df574-tpbqc                        1m           15Mi            
etcd-controller01-node-k8s                      7m           27Mi            
kube-apiserver-controller01-node-k8s            20m          271Mi           
kube-controller-manager-controller01-node-k8s   5m           45Mi            
kube-proxy-tj4zk                                1m           12Mi            
kube-scheduler-controller01-node-k8s            2m           17Mi            
weave-net-jhlcd                                 1m           37Mi   
```

From inside the controller node you can run any kubectl commands:
```
$ kubectl get nodes
NAME                    STATUS   ROLES           AGE     VERSION
controller01-node-k8s   Ready    control-plane   3m23s   v1.29.1
worker01-node-k8s       Ready    <none>          2m17s   v1.29.1
worker02-node-k8s       Ready    <none>          2m15s   v1.29.1
worker03-node-k8s       Ready    <none>          2m13s   v1.29.1
```

The scripts also set aliases for kubectl and the command to change the namespace in the current context. See examples below with a HA cluster:

```
$ k get nodes
NAME                STATUS   ROLES           AGE     VERSION
controller01-node   Ready    control-plane   5m19s   v1.29.1
controller02-node   Ready    control-plane   3m40s   v1.29.1
controller03-node   Ready    control-plane   2m59s   v1.29.1
worker01-node       Ready    <none>          2m53s   v1.29.1
```
```
$ kn kube-system
Context "kubernetes-admin@kubernetes" modified.
```
```
$ k get configmaps
NAME                                                   DATA   AGE
coredns                                                1      6m20s
extension-apiserver-authentication                     6      6m37s
kube-apiserver-legacy-service-account-token-tracking   1      6m37s
kube-proxy                                             2      6m20s
kube-root-ca.crt                                       1      6m22s
kubeadm-config                                         1      6m27s
kubelet-config                                         1      6m27s
weave-net                                              0      6m7s
```
Feel free to use this setup for your local dev environment, or just as a playground for learning Kubernetes. You can try the high availability setup as well to better mirror a live environment.

For learning purposes it is advised to practice the k8s deployment. If you plan to run an application on this cluster the k3s distribution is recommended since it is lighter and does not consume as much resources as k8s, leaving you with more CPU/Memory for your application.

## Kubernetes dashboard

Kubernetes Dashboard is a general purpose, web-based UI for Kubernetes clusters (https://github.com/kubernetes/dashboard).

The script will ask you if you want to install the kubernetes-dashboard GUI. If you install it, a local-admin service account will be created in the kubernetes-dashboard namespace together with a service account token secret. The token will serve as authentication against the kubernetes-dashboard API.

In order to connect to the kubernetes dashboard, you need to first proxy the requests to your localhost:

```
kubectl proxy
```
After that you can go to your browser and paste the URL below:

```
http://127.0.0.1:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#/login
```
Use the token in the *local-admin-token* secret from the kubernetes-dashboard namespace to authenticate:

```
kubectl describe secret --namespace=kubernetes-dashboard local-admin-token
```

## Using this tool to prepare for the CKA/CKS exams

Feel free to use this tool for your exam preparation. A few things you can try are:

1. Deploy a HA cluster and inspect the contents of /etc/kubernetes/pki directory on each controller node. What is the difference between controller01 and the other controllers?
2. Try to setup connectivity to the cluster directly from your local machine the hard way, without using the k8s CSR controller. You will need to generate a RSA key on your local machine and after that create the CSR with the necessary CN and group name contents (if you want to login as an admin user, use system:masters for the group.) This CSR needs to be signed from one of the controller nodes with their root CA private/public keys. You can try the commands bellow:

From local machine:
```
$ openssl genrsa -out local-admin.key 2048   
$ openssl req -new -key local-admin.key -subj \
"/CN=local-admin/O=system:masters" -out local-admin.csr
```

From controller node:
```
$ openssl x509 -req -in local-admin.csr -CA ca.crt -CAkey ca.key -out local-admin.crt
```
You can copy the contents of the kubeconfig file from the control node which signed your CSR. All you need to do is change the *client-certificate-data* and *client-key-data* fields with the values of your base64 encoded keys.

## Troubleshooting

### Mac with M3 chip
If you are using a machine with M3 chip, the latest multipass version will most likely not work. Please install version 1.11.1: https://github.com/canonical/multipass/releases/download/v1.11.1/multipass-1.11.1+mac-Darwin.pkg.

### Dhcp leases
When VMs are created/deleted, multipass does not release the IP addresses from the Mac's DHCP server (they are stored in /var/db/dhcpd_leases). If you create a cluster several times, make sure to reclaim the IP addresses by either:

1. Manually deleting the claimed addresses from /var/db/dhcpd_leases.
2. Run the *delete-cluster-manually.sh* script which, if allowed, will delete all entries from your /var/db/dhcpd_leases. If you do not want to delete all entries, prompt the script to skip the last step.

### Multipass commands timing out / Multipass not behaving as expected
After provisioning/destroying 50 clusters of different sizes, multipass began experiencing timeouts. Restarting the multipassd service will restore multipass to its initial working state.

```
$ sudo launchctl stop com.canonical.multipassd 
$ sudo launchctl start com.canonical.multipassd 
```

## FAQ

Q1. Can I run the *deploy-cluster.sh* script again without deleting any of the existing cluster VMs?

Answer: Yes, definitely! The scripts have the necessary built in logic that spot existing cluster VMs and will ask you if you want to delete them. If you answer with 'y', the script will delete existing ones and provision fresh VMs for the new cluster configuration you selected.

Q2. I have other machines running with multipass on my localhost. How do I safely run the *delete-cluster-manually.sh* script?

Answer: The *delete-cluster-manually.sh* script contains a step which purges all entries from the /var/db/dhcpd_leases file. If you have other VMs on your localhost, just answer with 'n' when prompted because you still want their entries in the /var/db/dhcpd_leases file. However it is recommended to purge the dhcpd_leases file regularly since it might lead to multipass issues if it has too many entries.

Q3. How does the *--dual-mode* flag work?

Answer: The *--dual-mode* flag enables you to have 2 clusters running simultaneously. It can be used to test multi-cluster deployments/networking, etc. It only accepts 2 node clusters. Its limitation is that it can only be run once sequentially. If you plan to run a second command with the *--dual-mode* flag it will prompt you to delete your existing deployment and create a new one.

## Components versions

This build uses the following component versions:

kubeadm, kubectl, kubelet: 1.29.1


containerd: 1.6.27  https://github.com/containerd/containerd/releases/download/v1.6.27/containerd-1.6.27-linux-arm64.tar.gz


crictl: 1.29.0  https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.29.0/crictl-v1.29.0-linux-arm64.tar.gz


runc: 1.1.7

k3s: v1.29.1+k3s2
