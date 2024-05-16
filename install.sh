#!/bin/bash

export KUBEVIRT_RELEASE=$(curl https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export K3S_VERSION=v1.28.7+k3s1

#Install tools 
if command -v apt-get > /dev/null 2>&1; then
    #Running on apt-based system
    sudo apt-get update
    sudo apt-get install -y bridge-utils net-tools network-manager git qemu-kvm libvirt-daemon-system libvirt-clients
    sudo systemctl enable libvirtd
    sudo systemctl start libvirtd
    
elif command -v dnf > /dev/null 2>&1; then
    #Running on dnf-based system
    sudo dnf update -y
    sudo dnf install -y bridge-utils net-tools git @virtualization
    sudo systemctl enable libvirtd
    sudo systemctl start libvirtd    
else
    echo "No compatible package manager found."
    exit 1
fi

#Get virtualization status
sudo virt-host-validate qemu

#Disable apparmor (if enabled)
sudo systemctl stop apparmor
sudo systemctl disable apparmor

#Install k3sup
curl -sLS https://get.k3sup.dev | sh
sudo install k3sup /usr/local/bin/

#Create bridges
sudo nmcli con add type bridge con-name brdmz ifname brdmz
sudo nmcli con up brdmz

sudo nmcli con add type bridge con-name brlan ifname brlan
sudo nmcli con up brlan

#Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin

#Install k3s kubernetes
k3sup install --local --k3s-version $K3S_VERSION --k3s-extra-args '--write-kubeconfig-mode=644 --disable traefik --flannel-backend=wireguard-native'
echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> ~/.bashrc
sleep 10

#Install multus
kubectl apply -f manifests/multus/multus-daemonset-thick.yml
#kubectl wait --for condition=Available daemonset.apps/kube-multus-ds -n kube-system --timeout=120s


#Install kubevirt
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_RELEASE}/kubevirt-operator.yaml
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_RELEASE}/kubevirt-cr.yaml
kubectl -n kubevirt wait kv kubevirt --for condition=Available --timeout=120s

#Install longhorn
kubectl apply -f manifests/longhorn/longhorn.yml