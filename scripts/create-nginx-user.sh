#!/usr/bin/env bash
set -euo pipefail

USER=nginx-user
NAMESPACE=nginx-demo
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA_CERT=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')


kubectl create namespace $NAMESPACE

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

kubectl certificate approve ${USER}

kubectl get csr ${USER} \
  -o jsonpath='{.status.certificate}' \
  | base64 --decode > ${USER}.crt

echo $CA_CERT |base64 --decode > ca.crt  

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

