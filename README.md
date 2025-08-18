# cc-intel-pccs

**Provisioning Certificate Caching Service (PCCS)** for caching collaterals required for quote generation and quote verification.

## Prerequisites

Ensure you have the following tools installed before proceeding:

- [Git](https://git-scm.com/downloads)
- [Helm](https://helm.sh/docs/intro/install/)
- [Kubectl](https://kubernetes.io/docs/setup/)

## Installation

Clone the repository and navigate to the project directory:

```bash
git clone https://github.com/scontain/cc-intel-pccs.git
cd cc-intel-pccs
```

### Deploy cert-manager

PCCS requires [cert-manager](https://cert-manager.io/) to issue TLS certificates. You must install cert-manager and its CRDs **before** deploying PCCS. Run the following commands:

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true

# Wait for cert-manager to be ready
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=120s
```

### Deploy PCCS

Build the Helm chart dependencies:

```sh
helm dependency build charts/pccs
```

Then deploy PCCS using Helm:

```bash
# if using k3d set persistentVolumeClaim.db.storageClassName and persistentVolumeClaim.logs.storageClassName to local-path
helm install pccs ./charts/pccs --namespace pccs --create-namespace --wait --set pccsConfig.apiKey=$DCAP_KEY
```

> **Important:** The `pccsConfig.apiKey` is required for PCCS to fetch provisioning certificates. If this value is not set, the installation will fail.

This command installs PCCS in the `pccs` namespace. If the namespace does not exist, it will be created automatically.

## How to interact with

To interact with PCCS, use `kubectl port-forward` and `curl`:

```bash
kubectl port-forward -n pccs pod/pccs-0 8081:8081 &
curl -k https://$PCCS_URL:8081/sgx/certification/v4/rootcacrl
```

### When using k3d

To allow local access using your PCCS URL, add it to `/etc/hosts`:

```bash
echo "127.0.0.1 $PCCS_URL" >> /etc/hosts
curl -k https://$PCCS_URL:8081/sgx/certification/v4/rootcacrl
```

## Uninstallation

To remove PCCS from your cluster, run:

```bash
helm uninstall pccs --namespace pccs
```

(Optional) To delete the namespace as well:

```bash
kubectl delete namespace pccs
```
