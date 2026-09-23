#!/usr/bin/env bash

# Installs the CLI tools the test environment needs when they are missing:
#
#   bash tests/install-tools.sh helm|k3d|kubectl
#
# The versions come from the environment: config.env for local runs, the env
# block of .github/workflows/pr.yml for CI. Source config.env first when
# running this script by hand.

set -euo pipefail

install_helm() {
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

install_k3d() {
  : "${K3D_VERSION:?K3D_VERSION must be set (e.g. v5.9.0)}"
  curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG="$K3D_VERSION" bash
}

install_kubectl() {
  : "${KUBECTL_VERSION:?KUBECTL_VERSION must be set (e.g. v1.32.5)}"
  local workdir
  workdir=$(mktemp -d)
  trap 'rm -rf "$workdir"' RETURN

  curl -fsSL -o "$workdir/kubectl" "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl"
  curl -fsSL -o "$workdir/kubectl.sha256" "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl.sha256"
  echo "$(cat "$workdir/kubectl.sha256")  $workdir/kubectl" | sha256sum --check
  install -m 0755 "$workdir/kubectl" /usr/local/bin/kubectl
}

case "${1:-}" in
  helm)    install_helm ;;
  k3d)     install_k3d ;;
  kubectl) install_kubectl ;;
  *)
    echo "Usage: $0 helm|k3d|kubectl" >&2
    exit 2
    ;;
esac
