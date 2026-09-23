#!/bin/bash

set -euo pipefail

source ./tests/utils.sh

info "----------------------------------------------------------"
info "| SETUP ENVIRONMENT: Ensuring dependencies are installed |"
info "----------------------------------------------------------"

# ensure_installed checks if a program ($cmd_friendly_name)
# is installed using $check_cmd. If not installed,
# it installs the program with help of $install_cmd; the installer's output
# goes to a log file (see run_quiet in tests/utils.sh).
function ensure_installed {
    local cmd_friendly_name=$1
    local check_cmd=$2
    local install_cmd=$3
    if $check_cmd > /dev/null 2>&1; then
        echo -e "${GREEN}ok${NC}  $cmd_friendly_name (already installed)"
        return
    fi
    run_quiet "install-$cmd_friendly_name" ${SUDO:+"$SUDO"} \
        env K3D_VERSION="${K3D_VERSION:-}" KUBECTL_VERSION="${KUBECTL_VERSION:-}" \
        bash -c "$install_cmd"
}

APT_INSTALL="apt-get update -y && apt-get install -y"
ensure_installed "csvtool" "csvtool -help" "$APT_INSTALL csvtool"
ensure_installed "curl" "curl --version" "$APT_INSTALL curl"
ensure_installed "helm" "helm version" "bash tests/install-tools.sh helm"
ensure_installed "k3d" "k3d version" "bash tests/install-tools.sh k3d"
ensure_installed "kubectl" "kubectl version --client" "bash tests/install-tools.sh kubectl"
ensure_installed "xxd" "xxd -v" "$APT_INSTALL xxd"

# No SGX runtime install: PCKIDRetrievalTool ships its own libsgx_urts and
# tests/utils.sh run_pckid_retrieval points LD_LIBRARY_PATH at it.

info "--------------------------------------------"
info "| SETUP ENVIRONMENT: Creating k3d cluster  |"
info "--------------------------------------------"

# k3s ships Traefik as its ingress controller; k3d forwards host ports 80/443 to
# its LoadBalancer Service, so https://$PCCS_URL on 127.0.0.1 reaches PCCS
# through the chart's Ingress.
run_quiet "k3d-cluster-create" k3d cluster create "$CLUSTER_NAME" -a 2 \
  -p "80:80@loadbalancer" \
  -p "443:443@loadbalancer"

info "-----------------------------------------------------"
info "| SETUP ENVIRONMENT: Verifying cluster connectivity |"
info "-----------------------------------------------------"

run_quiet "kubectl-cluster-info" kubectl cluster-info

k3d kubeconfig get "$CLUSTER_NAME" > "$KUBECONFIG"

info "----------------------------------------------"
info "| SETUP ENVIRONMENT: Installing cert-manager |"
info "----------------------------------------------"

# The chart version comes from the environment: config.env for local runs,
# the env block of .github/workflows/pr.yml for CI.
: "${CERT_MANAGER_VERSION:?CERT_MANAGER_VERSION must be set (e.g. v1.18.2)}"

run_quiet "helm-repo-add-jetstack" helm repo add --force-update jetstack https://charts.jetstack.io
run_quiet "helm-repo-update" helm repo update jetstack

run_quiet "helm-install-cert-manager" helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version "$CERT_MANAGER_VERSION" \
  --set crds.enabled=true

run_quiet "cert-manager-rollout" kubectl rollout status deployment/cert-manager -n cert-manager --timeout=120s

info "------------------------------------------------------"
info "| SETUP ENVIRONMENT: Waiting for Traefik ingress class |"
info "------------------------------------------------------"

# k3s deploys Traefik through a HelmChart resource after the API server is up,
# so the IngressClass can appear a little after "cluster create" returns.
for _ in $(seq 1 30); do
  kubectl get ingressclass traefik > /dev/null 2>&1 && break
  sleep 5
done
run_quiet "traefik-ingressclass" kubectl get ingressclass traefik
run_quiet "traefik-rollout" kubectl rollout status deployment/traefik -n kube-system --timeout=180s

info "---------------------------------------"
info "| SETUP ENVIRONMENT: Deploying PCCS   |"
info "---------------------------------------"

USER_TOKEN_HASH=$(echo -n "$PCCS_USER_TOKEN" | sha512sum | awk '{print $1}')
ADMIN_TOKEN_HASH=$(echo -n "$PCCS_ADMIN_TOKEN" | sha512sum | awk '{print $1}')

run_quiet "helm-dependency-build-pccs" helm dependency build charts/pccs
run_quiet "helm-install-pccs" helm install pccs ./charts/pccs --namespace pccs --create-namespace --wait --timeout 5m \
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
