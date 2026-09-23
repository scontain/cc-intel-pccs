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
    if ! $check_cmd >> /dev/null 2>&1; then
        echo "$cmd_friendly_name not installed... Installing..."
        $SUDO apt-get update -y
        $SUDO env K3D_VERSION="${K3D_VERSION:-}" KUBECTL_VERSION="${KUBECTL_VERSION:-}" \
            bash -c "$install_cmd"
    fi
    echo -e "${GREEN}$cmd_friendly_name Installed.${NC}"
}

ensure_installed "csvtool" "csvtool -help" "apt-get install -y csvtool"
ensure_installed "curl" "curl --version" "apt-get install -y curl"
ensure_installed "helm" "helm version" "bash tests/install-tools.sh helm"
ensure_installed "k3d" "k3d version" "bash tests/install-tools.sh k3d"
ensure_installed "kubectl" "kubectl version --client" "bash tests/install-tools.sh kubectl"
ensure_installed "xxd" "xxd -v" "apt-get install -y xxd"

info "------------------------------------------------------"
info "| Installing Intel SGX runtime libraries (sgx_urts.so) |"
info "------------------------------------------------------"

if ! sgx_device_present; then
    echo "No SGX device found, skipping SGX runtime installation."
elif ldconfig -p 2>/dev/null | grep -q "sgx_urts"; then
    echo "SGX runtime already installed."
elif find /usr/lib /usr/lib64 /opt/intel /lib /lib64 -name "libsgx_urts.so*" 2>/dev/null | grep -q "sgx_urts.so"; then
    echo "SGX runtime already installed (detected via filesystem)."
else
    echo "SGX runtime not found. Installing..."
    $SUDO apt-get update -y
    $SUDO apt-get install -y lsb-release wget gnupg

    UBUNTU_CODENAME=$(lsb_release -cs)
    echo "Detected Ubuntu codename: $UBUNTU_CODENAME"

    # Try to install from Ubuntu repositories first
    if ! $SUDO apt-get install -y libsgx-enclave-common libsgx-urts libsgx-epid libsgx-quote-ex; then
        echo "Falling back to Intel repository for $UBUNTU_CODENAME..."
        wget -qO - https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key \
            | gpg --dearmor | $SUDO tee /usr/share/keyrings/intel-sgx.gpg > /dev/null
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/intel-sgx.gpg] https://download.01.org/intel-sgx/sgx_repo/ubuntu $UBUNTU_CODENAME main" \
            | $SUDO tee /etc/apt/sources.list.d/intel-sgx.list > /dev/null
        $SUDO apt-get update -y
        $SUDO apt-get install -y libsgx-enclave-common libsgx-urts libsgx-epid libsgx-quote-ex
    fi

    echo "SGX runtime installation completed successfully."
fi

info "--------------------------------------------"
info "| SETUP ENVIRONMENT: Creating k3d cluster  |"
info "--------------------------------------------"

# k3s ships Traefik as its ingress controller; k3d forwards host ports 80/443 to
# its LoadBalancer Service, so https://$PCCS_URL on 127.0.0.1 reaches PCCS
# through the chart's Ingress.
k3d cluster create "$CLUSTER_NAME" -a 2 \
  -p "80:80@loadbalancer" \
  -p "443:443@loadbalancer"

info "-----------------------------------------------------"
info "| SETUP ENVIRONMENT: Verifying cluster connectivity |"
info "-----------------------------------------------------"

kubectl cluster-info

k3d kubeconfig get "$CLUSTER_NAME" > "$KUBECONFIG"

info "----------------------------------------------"
info "| SETUP ENVIRONMENT: Installing cert-manager |"
info "----------------------------------------------"

# The chart version comes from the environment: config.env for local runs,
# the env block of .github/workflows/pr.yml for CI.
: "${CERT_MANAGER_VERSION:?CERT_MANAGER_VERSION must be set (e.g. v1.18.2)}"

helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version "$CERT_MANAGER_VERSION" \
  --set crds.enabled=true

warn "Waiting for cert-manager to be ready..."
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=120s

info "------------------------------------------------------"
info "| SETUP ENVIRONMENT: Waiting for Traefik ingress class |"
info "------------------------------------------------------"

# k3s deploys Traefik through a HelmChart resource after the API server is up,
# so the IngressClass can appear a little after "cluster create" returns.
for _ in $(seq 1 30); do
  kubectl get ingressclass traefik > /dev/null 2>&1 && break
  sleep 5
done
kubectl get ingressclass traefik
kubectl rollout status deployment/traefik -n kube-system --timeout=180s

info "---------------------------------------"
info "| SETUP ENVIRONMENT: Deploying PCCS   |"
info "---------------------------------------"

USER_TOKEN_HASH=$(echo -n "$PCCS_USER_TOKEN" | sha512sum | awk '{print $1}')
ADMIN_TOKEN_HASH=$(echo -n "$PCCS_ADMIN_TOKEN" | sha512sum | awk '{print $1}')

helm dependency build charts/pccs
helm install pccs ./charts/pccs --namespace pccs --create-namespace --wait --timeout 5m \
  --set replicas=1 \
  --set image.repository="$PCCS_IMAGE_REPOSITORY" \
  --set image.tag="$PCCS_IMAGE_TAG" \
  --set ingress.enabled=true \
  --set ingress.className=traefik \
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
  echo "$LINE" | $SUDO tee -a /etc/hosts > /dev/null
  echo -e "${GREEN}Done.${NC}"
fi
