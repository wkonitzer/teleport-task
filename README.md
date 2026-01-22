# Kubernetes Bare-Metal Lab (Parallels)

This guide walks through setting up a small Kubernetes cluster using **kubeadm**, **Calico**, **MetalLB**, **cert-manager**, and **NGINX Ingress** on local VMs running in **Parallels**.

Design decisions are in the docs subdirectory.

---

## Prerequisites

- Parallels Desktop
- Linux VMs (Ubuntu recommended)
- Internet access from all VMs

---

## 1. Create Virtual Machines

Create **3 VMs** in Parallels with the following specifications:

### Controller Node
- CPUs: 4  
- RAM: 8 GB  
- Disk: 20 GB  

### Worker Nodes (x2)
- CPUs: 4  
- RAM: 4 GB  
- Disk: 20 GB  

---

## 2. Clone this repo onto the controller node

```bash
git clone https://github.com/wkonitzer/teleport-task.git
```

## 3. Install Kubernetes Dependencies

On **all nodes** (controller + workers), copy and run the k8s-install.sh script in the scripts directory:

```bash
sudo bash k8s-install.sh
```

---

## 4. Reboot Nodes

```bash
sudo reboot
```

---

## 5. Initialize the Kubernetes Cluster

On the **controller node**:

```bash
sudo kubeadm init --pod-network-cidr=192.168.0.0/16
```

---

## 6. Configure kubectl (Controller Node)

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Logout and in again to pick up the new config

---

## 7. Install Calico CNI

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
```

Verify:

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

Wait until all pods are "Running" before continuing.
---

## 8. Join Worker Nodes

Generate join command:

```bash
kubeadm token create --print-join-command
```

Run on each worker:

```bash
sudo kubeadm join <controller-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

Verify:

```bash
kubectl get nodes
```

---

## 9. Install Helm

```bash
sudo curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
```

---

## 10. Install cert-manager

```bash
curl -LO https://cert-manager.io/public-keys/cert-manager-keyring-2021-09-20-1020CF3C033D4F35BAE1C19E1226061C665DF13E.gpg
```

```bash
helm install \
  cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.19.2 \
  --namespace cert-manager \
  --create-namespace \
  --verify \
  --keyring ./cert-manager-keyring-2021-09-20-1020CF3C033D4F35BAE1C19E1226061C665DF13E.gpg \
  --set crds.enabled=true
```

Verify:

```bash
kubectl get pods -n cert-manager
```

---

## 11. Create Internal CA

```bash
openssl genrsa -out cacertman.key 4096

openssl req -x509 -new -nodes -key cacertman.key \
  -subj "/CN=internal-ca" \
  -days 3650 \
  -out cacertman.crt
```

---

## 12. Trust the CA

```bash
sudo cp cacertman.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

---

## 13. Create CA Secret

```bash
kubectl create secret tls internal-ca --cert=cacertman.crt --key=cacertman.key -n cert-manager
```

---

## 14. Create ClusterIssuer

```bash
kubectl apply -f certman/clusterissuer.yaml
```

---

## 15. Install NGINX Ingress

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
```

```bash
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"LoadBalancer"}}'
```

Verify:

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

---

## 16. Install MetalLB

```bash
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb --namespace metallb-system --create-namespace
```

```bash
kubectl apply -f metallb/ip_address_pool.yaml
kubectl apply -f metallb/l2-advertisement.yaml
```

---

## 17. Add Hosts Entry

```bash
echo "192.168.99.2 nginx.local" | sudo tee -a /etc/hosts > /dev/null
```

---

## 18. Create NGINX User

```bash
sudo bash scripts/create-nginx-user.sh
```

Verify:

```bash
kubectl get pods -n kube-system --kubeconfig nginx-user.kubeconfig
kubectl get pods -n nginx-demo --kubeconfig nginx-user.kubeconfig
```

---

## 19. Deploy NGINX App

```bash
helm install nginx ./nginx   --namespace nginx-demo   --kubeconfig nginx-user.kubeconfig
```

---

## 20. Verify

```bash
kubectl get pods -n nginx-demo --kubeconfig nginx-user.kubeconfig
kubectl get certificate --kubeconfig nginx-user.kubeconfig
curl -L nginx.local
```

Expected output:

```
Deployed by a non-admin Kubernetes user
```

