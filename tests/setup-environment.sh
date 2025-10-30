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

info "------------------------------------------------------"
info "| Installing Intel SGX runtime libraries (sgx_urts.so) |"
info "------------------------------------------------------"

if ldconfig -p 2>/dev/null | grep -q "sgx_urts"; then
    echo "SGX runtime already installed."
elif find /usr/lib /usr/lib64 /opt/intel /lib /lib64 -name "libsgx_urts.so*" 2>/dev/null | grep -q "sgx_urts.so"; then
    echo "SGX runtime already installed (detected via filesystem)."
else
    echo "SGX runtime not found. Installing..."
    apt update -y
    apt install -y lsb-release wget gnupg

    UBUNTU_CODENAME=$(lsb_release -cs)
    echo "Detected Ubuntu codename: $UBUNTU_CODENAME"

    # Try to install from Ubuntu repositories first
    if ! apt install -y libsgx-enclave-common libsgx-urts libsgx-epid libsgx-quote-ex; then
        echo "Falling back to Intel repository for $UBUNTU_CODENAME..."
        wget -qO - https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key | apt-key add -
        echo "deb [arch=amd64] https://download.01.org/intel-sgx/sgx_repo/ubuntu $UBUNTU_CODENAME main" \
            > /etc/apt/sources.list.d/intel-sgx.list
        apt update -y
        apt install -y libsgx-enclave-common libsgx-urts libsgx-epid libsgx-quote-ex
    fi

    echo "SGX runtime installation completed successfully."
fi

info "--------------------------------------------"
info "| SETUP ENVIRONMENT: Creating k3d cluster  |"
info "--------------------------------------------"

k3d cluster create "$CLUSTER_NAME" -a 2 \
  -p "80:80@loadbalancer" \
  -p "443:443@loadbalancer" \
  --k3s-arg "--disable=traefik@server:0"

info "-----------------------------------------------------"
info "| SETUP ENVIRONMENT: Verifying cluster connectivity |"
info "-----------------------------------------------------"

kubectl cluster-info

k3d kubeconfig get "$CLUSTER_NAME" > "$KUBECONFIG"

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

USER_TOKEN_HASH=$(echo -n "$PCCS_USER_TOKEN" | sha512sum | awk '{print $1}')
ADMIN_TOKEN_HASH=$(echo -n "$PCCS_ADMIN_TOKEN" | sha512sum | awk '{print $1}')

helm dependency build charts/pccs
helm install pccs ./charts/pccs --namespace pccs --create-namespace --wait \
  --set replicas=1 \
  --set ingress.host="$PCCS_URL" \
  --set pccsConfig.apiKey="$DCAP_KEY" \
  --set pccsConfig.logLevel=debug \
  --set pccsConfig.userTokenHash="$USER_TOKEN_HASH" \
  --set pccsConfig.adminTokenHash="$ADMIN_TOKEN_HASH" \
  --set persistentVolumeClaim.logs.storageClassName=local-path \
  --set persistentVolumeClaim.db.storageClassName=local-path \
  --set imagePullSecrets.enabled=true \
  --set imagePullSecrets.data.username="$IMAGE_USERNAME" \
  --set imagePullSecrets.data.password="$IMAGE_PASSWORD" \
  --set imagePullSecrets.data.email="$IMAGE_EMAIL" \
  --set imagePullSecrets.data.registry="$IMAGE_REGISTRY"

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
