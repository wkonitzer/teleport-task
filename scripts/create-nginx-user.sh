#!/usr/bin/env bash
set -euo pipefail

# One downside of client-cert auth is lifecycle management — expiration and 
# rotation are manual unless you automate it.

# This script is intentionally not idempotent.
# User creation and certificate issuance are treated as explicit,
# security-sensitive operations rather than repeatable automation.


# ----------------------------
# 1. Create variables
# ----------------------------
USER=nginx-user
NAMESPACE=nginx-demo
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA_CERT=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# ----------------------------
# 2. Create namespace
# ----------------------------
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# ----------------------------
# 3. Generate key and certificate signing request
# ----------------------------
openssl genrsa -out ${USER}.key 2048

openssl req -new \
  -key ${USER}.key \
  -out ${USER}.csr \
  -subj "/CN=${USER}/O=${NAMESPACE}"

cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USER}
spec:
  request: $(base64 < ${USER}.csr | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF

# ----------------------------
# 4. Approve signing request
# In production, CSR approval would typically be performed
# by a cluster admin or automated policy controller
# ----------------------------
kubectl certificate approve ${USER}

# ----------------------------
# 5. Download certificates
# ----------------------------
kubectl get csr ${USER} \
  -o jsonpath='{.status.certificate}' \
  | base64 --decode > ${USER}.crt

echo $CA_CERT |base64 --decode > ca.crt  

# ----------------------------
# 6. Create User Role and Bindings
# ----------------------------
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: nginx-role
  namespace: ${NAMESPACE}
rules:
- apiGroups: [""]
  resources:
    - pods
    - services
    - configmaps
    - secrets
  verbs:
    - get
    - list
    - watch
    - create
    - update
    - patch
    - delete
- apiGroups: ["apps"]
  resources:
    - deployments
  verbs:
    - get
    - list
    - watch
    - create
    - update
    - patch
    - delete
- apiGroups: ["networking.k8s.io"]
  resources:
    - ingresses
  verbs:
    - get
    - list
    - watch
    - create
    - update
    - patch
    - delete
EOF

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: nginx-binding
  namespace: ${NAMESPACE}
subjects:
- kind: Group
  name: ${NAMESPACE}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: nginx-role
  apiGroup: rbac.authorization.k8s.io
EOF

# ----------------------------
# 7. Create Kubeconfig file
# ----------------------------
kubectl config --kubeconfig=${USER}.kubeconfig set-cluster ${CLUSTER_NAME} \
  --server=${API_SERVER} \
  --certificate-authority=ca.crt

kubectl config --kubeconfig=${USER}.kubeconfig set-credentials ${USER} \
  --client-certificate=${USER}.crt \
  --client-key=${USER}.key \
  --embed-certs=true

kubectl config --kubeconfig=${USER}.kubeconfig set-context ${USER}@${CLUSTER_NAME} \
  --cluster=${CLUSTER_NAME} \
  --user=${USER} \
  --namespace=${NAMESPACE}

kubectl config --kubeconfig=${USER}.kubeconfig use-context ${USER}@${CLUSTER_NAME}

