#!/bin/bash

set -euo pipefail

source ./tests/utils.sh

info "----------------------------------------------------------"
info "| SETUP ENVIRONMENT: Ensuring dependencies are installed |"
info "----------------------------------------------------------"

# ensure_installed checks if a program ($cmd_friendly_name)
# is installed using $check_cmd. If not installed,
# it installs the program with help of $install_cmd.
function ensure_installed {
    local cmd_friendly_name=$1
    local check_cmd=$2
    local install_cmd=$3
    echo "Ensuring $cmd_friendly_name is installed..."
    if ! $check_cmd >> /dev/null; then
        echo "$cmd_friendly_name not installed... Installing..."
        apt update
        $install_cmd
    fi
    echo -e "${GREEN}$cmd_friendly_name Installed.${NC}"
}

ensure_installed "csvtool" "csvtool -help" "apt install -y csvtool"
ensure_installed "curl" "curl --version" "apt install -y curl"
ensure_installed "helm" "helm --help" "bash install/helm.sh"
ensure_installed "k3d" "k3d --version" "bash install/k3d.sh"
ensure_installed "kubectl" "kubectl --help" "bash install/kubectl.sh"
ensure_installed "xxd" "xxd -v" "apt install -y xxd"

info "--------------------------------------------"
info "| SETUP ENVIRONMENT: Creating k3d cluster  |"
info "--------------------------------------------"

k3d cluster create $CLUSTER_NAME -a 2 \
  -p "80:80@loadbalancer" \
  -p "443:443@loadbalancer" \
  --k3s-arg "--disable=traefik@server:0"

info "-----------------------------------------------------"
info "| SETUP ENVIRONMENT: Verifying cluster connectivity |"
info "-----------------------------------------------------"

kubectl cluster-info

k3d kubeconfig get $CLUSTER_NAME > $KUBECONFIG

info "----------------------------------------------"
info "| SETUP ENVIRONMENT: Installing cert-manager |"
info "----------------------------------------------"

helm repo add jetstack https://charts.jetstack.io
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

warn "Waiting for cert-manager to be ready..."
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=120s

info "---------------------------------------"
info "| SETUP ENVIRONMENT: Deploying PCCS   |"
info "---------------------------------------"

helm dependency build charts/pccs
helm install pccs ./charts/pccs --namespace pccs --create-namespace \
  --set pccsConfig.apiKey=$DCAP_KEY \
  --set ingress.host=$PCCS_URL \
  --set pccsConfig.logLevel=debug \
  --set pccsConfig.userTokenHash=$PCCS_USER_TOKEN \
  --set persistentVolumeClaim.logs.storageClassName=local-path \
  --set persistentVolumeClaim.db.storageClassName=local-path \
  --set imagePullSecrets.enabled=true \
  --set imagePullSecrets.data.username=$IMAGE_USERNAME \
  --set imagePullSecrets.data.password=$IMAGE_PASSWORD \
  --set imagePullSecrets.data.email=$IMAGE_EMAIL \
  --set imagePullSecrets.data.registry=$IMAGE_REGISTRY

info "---------------------------------------------"
info "| SETUP ENVIRONMENT: Configuring /etc/hosts |"
info "---------------------------------------------"

LINE="127.0.0.1 $PCCS_URL"

if grep -qxF "$LINE" /etc/hosts; then
  echo "Entry for $PCCS_URL already exists in /etc/hosts"
else
  echo "Adding $LINE to /etc/hosts"
  echo "$LINE" | tee -a /etc/hosts > /dev/null
  echo -e "${GREEN}Done.${NC}"
fi
