# cc-intel-pccs

Intel **Provisioning Certificate Caching Service (PCCS)** for caching collaterals required for quote generation and quote verification.

1. [Prerequisites](#prerequisites)
1. [Create cluster](#create-cluster)
1. [Installation](#installation)
   * [Deploy cert-manager](#deploy-cert-manager)
   * [Deploy PCCS](#deploy-pccs)
   * [Deploy monitoring stack (Optional)](#deploy-monitoring-stack-optional)
1. [Interacting with PCCS](#how-to-interact-with)
1. [Uninstallation](#uninstallation)
1. [Running Tests](#running-tests)

## Prerequisites

Ensure you have the following tools installed before proceeding:

* [Git](https://git-scm.com/downloads)
* [Helm](https://helm.sh/docs/intro/install/)
* [Kubectl](https://kubernetes.io/docs/setup/)
* [K3d](k3d.io) *Optional*

## Create cluster

Before deploying PCCS, make sure you are connected to the target Kubernetes cluster. You can either **create a new cluster** (e.g., using `k3d`) or **point your environment** to an existing one by setting the `KUBECONFIG` variable.

To create a new local cluster with `k3d`, run:

```bash
k3d cluster create pccs-cluster \
  --agents 2 \
  -p "80:80@loadbalancer" \
  -p "443:443@loadbalancer" \
  --k3s-arg "--disable=traefik@server:0"
```

> 💡 **Tip:**
> If you already have a cluster, simply set your environment to use it:
>
> ```bash
> export KUBECONFIG=/path/to/your/cluster/kubeconfig
> ```

## Installation

Clone the repository and navigate to the project directory:

```bash
git clone https://github.com/scontain/cc-intel-pccs.git
cd cc-intel-pccs
```

### Deploy cert-manager

PCCS requires [cert-manager](https://cert-manager.io/) to issue TLS certificates. You must install cert-manager and its CRDs **before** deploying PCCS.

> 💡 **Tip:** If cert-manager is already installed in your cluster, you do not need to reinstall it. Instead, simply point your PCCS `values.yaml` to the existing cert-manager instance by configuring the following section:
>
> ```yaml
> # values.yaml
> certManager:
> 
>   # Enables automatic TLS certificate management via cert-manager
>   enabled: true
> 
>   # Configuration for the ACME certificate issuer
>   issuer:
> 
>     # The name used to identify this cert-manager Issuer or ClusterIssuer
>     name: "pccs-issuer"
> 
>     # The type of issuer to create. Supported values:
>     # - "acme": Use ACME protocol (e.g., Let's Encrypt) to obtain certificates.
>     # - "selfSigned": Create a self-signed issuer for local or testing use.
>     type: selfSigned
> 
>     # URL of the ACME server to use for issuing certificates (only used if type is "acme").
>     # Use Let's Encrypt staging URL for testing:
>     #   https://acme-staging-v02.api.letsencrypt.org/directory
>     # Use Let's Encrypt production URL for live certificates:
>     #   https://acme-v02.api.letsencrypt.org/directory
>     server: "https://acme-staging-v02.api.letsencrypt.org/directory"
> 
>     # Contact email address for certificate expiration notices and ACME registration
>     # (only used if type is "acme").
>     email: "example@mymail.com"
> ```

Run the following commands:

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

Before deploying, you **must set your Intel DCAP API key** as an environment variable. If not provided, the PCCS service will fail to start and certificate retrieval will not work.

```bash
export DCAP_KEY=<your-intel-dcap-api-key>
```

> 💡 **Tip:** If your container images are hosted in a **private registry**, export the following environment variables before deploying.
>
> ```bash
> export IMAGE_USERNAME=<your-docker-username>
> export IMAGE_PASSWORD=<your-docker-password-or-token>
> export IMAGE_EMAIL=<your-docker-email>
> export IMAGE_REGISTRY=<your-docker-registry-url>  # e.g. https://index.docker.io/v1/
> ```

#### 1. Build Helm chart dependencies

```bash
helm dependency build charts/pccs
```

#### 2. Deploy PCCS using Helm

For a quick deployment using default settings, run (remember that DCAP is mandatory):

```bash
helm install pccs ./charts/pccs --namespace pccs --create-namespace --wait \
  --set pccsConfig.apiKey=$DCAP_KEY \
```

For **local environments** (e.g., `k3d`), run the following command:

```bash
helm install pccs ./charts/pccs --namespace pccs --create-namespace --wait \
  --set replicas=1 \
  --set ingress.host=pccs.example.com \
  --set pccsConfig.apiKey=$DCAP_KEY \
  --set pccsConfig.logLevel=debug \
  --set persistentVolumeClaim.logs.storageClassName=local-path \
  --set persistentVolumeClaim.db.storageClassName=local-path \
  --set imagePullSecrets.enabled=true \
  --set imagePullSecrets.data.username=$IMAGE_USERNAME \
  --set imagePullSecrets.data.password=$IMAGE_PASSWORD \
  --set imagePullSecrets.data.email=$IMAGE_EMAIL \
  --set imagePullSecrets.data.registry=$IMAGE_REGISTRY
```

> 💡 **Tip:**
> For a full list of configurable Helm values (ingress, persistence, TLS, logging, etc.), see [`charts/pccs/values.yaml`](./charts/pccs/values.yaml).

### Deploy monitoring stack (Optional)

Set up a monitoring and logging stack using Helm. This includes:

* **Blackbox Exporter** → External endpoint monitoring (HTTP, HTTPS, TCP, ICMP) and latency measurement
* **Prometheus** → Metrics collection
* **Loki** → Centralized log aggregation
* **Grafana** → Metrics and logs visualization

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
  --version 6.43.0 --namespace monitoring --create-namespace
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

Last but not least, import the preconfigured dashboard (`monitoring/grafana-dashboard.json`) through the web interface to see some interesting metrics.

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
