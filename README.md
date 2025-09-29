# cc-intel-pccs

**Provisioning Certificate Caching Service (PCCS)** for caching collaterals required for quote generation and quote verification.

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
   * [Deploy cert-manager](#deploy-cert-manager)
   * [Deploy PCCS](#deploy-pccs)
   * [Deploy monitoring stack](#deploy-monitoring-stack)
3. [Interacting with PCCS](#how-to-interact-with)
4. [Uninstallation](#uninstallation)
5. [Running Tests](#running-tests)

Use this table of contents to quickly jump to the desired section.

## Prerequisites

Ensure you have the following tools installed before proceeding:

* [Git](https://git-scm.com/downloads)
* [Helm](https://helm.sh/docs/intro/install/)
* [Kubectl](https://kubernetes.io/docs/setup/)

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

helm install cert-manager jetstack/cert-manager --set installCRDs=true \
  --version v1.18.2 --namespace cert-manager --create-namespace

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

### Deploy monitoring stack

Set up a monitoring and logging stack using Helm. This includes:

* **Blackbox Exporter** → External endpoint monitoring (HTTP, HTTPS, TCP, ICMP) and latency measurement.
* **Prometheus** → Metrics collection.
* **Loki** → Centralized log aggregation.
* **Grafana** → Metrics and logs visualization.

#### 1. Add Helm repositories

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

#### 2. Install Blackbox Exporter

Before running the command bellow, change the PCCS addres as needed.

```bash
helm install blackbox-exporter prometheus-community/prometheus-blackbox-exporter -f monitoring/blackbox-values.yaml \
  --version 11.3.1 --namespace monitoring --create-namespace
```

#### 3. Install Prometheus

```bash
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version 77.11.0 --namespace monitoring --create-namespace
```

Then, apply your custom probes:

```bash
kubectl apply -f monitoring/prometheus-probe.yaml
```

#### 4. Install Loki

```bash
helm install loki grafana/loki -f monitoring/loki-values.yaml \
  --version 3.5.3 --namespace monitoring --create-namespace
```

#### 5. Install Grafana with automatic datasources

Install Grafana using the file (remember to change user and password):

```bash
helm install grafana grafana/grafana -f monitoring/grafana-sources.yaml \
  --set adminUser=admin --set adminPassword=admin \
  --version 10.0.0 --namespace monitoring --create-namespace
```

#### 6. Access Grafana

```bash
kubectl port-forward -n monitoring svc/grafana 3000:80
```

* Open [http://localhost:3000](http://localhost:3000) in your browser.
* Default login: `admin` / `admin`.

Last but not least, apply the `monitoring/grafana-dashboard.yaml` to see some interesting metrics.

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
curl -k https://$PCCS_URL/sgx/certification/v4/rootcacrl
```

## Uninstallation

### Remove PCCS

To remove PCCS from your cluster:

```bash
helm uninstall pccs --namespace pccs
```

(Optional) To delete the namespace as well:

```bash
kubectl delete namespace pccs
```

### Remove Monitoring Stack

To remove Prometheus, Grafana, and Loki:

```bash
helm uninstall kube-prometheus-stack --namespace monitoring
helm uninstall grafana --namespace monitoring
helm uninstall loki --namespace monitoring
helm uninstall blackbox-exporter --namespace monitoring

# Optionally, delete the namespace
kubectl delete namespace monitoring
```

### Remove Cert-Manager

To remove Cert-Manager:

```bash
helm uninstall cert-manager --namespace cert-manager

# Optionally, delete the namespace
kubectl delete namespace cert-manager
```

## Running Tests

### Environment Setup

Copy the sample configuration and update values as needed:

```bash
cp config.env .env
# edit .env with your preferred values
sudo su
source .env
```

### Execute Tests

Run all tests with:

```bash
bash tests/run-all.sh
```

What this script does:

1. Creates a temporary working directory under tests/tmp for intermediate files
1. Installs required dependencies if missing
1. Creates a local k3d cluster with 2 agents
1. Installs cert-manager for TLS certificate management
1. Deploys PCCS with Helm
1. Updates /etc/hosts to map the PCCS URL locally
1. Installs PCKIDRetrievalTool
1. Tests platform registration and package management
1. Runs PCCS API tests

### Teardown

To fully clean up your environment after testing, simply run:

```bash
bash ./tests/teardown.sh
```

This script will:

1. Clean up any `/etc/hosts` entries related to `$PCCS_URL`.
1. Delete the **k3d cluster**.
