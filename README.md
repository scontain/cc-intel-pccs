# cc-intel-pccs

Intel **Provisioning Certificate Caching Service (PCCS)** for caching collaterals required for quote generation and quote verification.

1. [Prerequisites](#prerequisites)
1. [Create cluster](#create-cluster)
1. [Installation](#installation)
   * [Deploy cert-manager](#deploy-cert-manager)
   * [Deploy PCCS](#deploy-pccs)
   * [Deploy monitoring stack (Optional)](#deploy-monitoring-stack-optional)
1. [Interacting with PCCS](#how-to-interact-with)
1. [Teardown](#teardown)
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

PCCS requires [cert-manager](https://cert-manager.io/) to issue TLS certificates. You must have cert-manager installed and its CRDs **before** deploying PCCS.

> 💡 **Tip:** Already have cert-manager installed? Skip the installation and just point PCCS to your existing instance. [View configuration details](https://github.com/scontain/cc-intel-pccs/blob/main/charts/pccs/values.yaml#L216-L238).

To install run the following commands:

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager --set installCRDs=true \
  --version v1.18.2 --namespace cert-manager --create-namespace

# Wait for cert-manager to be ready
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=120s
```

### Exposing PCCS (Important)

This chart does not install an Ingress controller by default. You must choose one of the following methods to expose the PCCS service.

1. **Use an ingress controller (recommended)**

    If your cluster already has an Ingress controller (e.g., NGINX, Traefik), add `--set ingress.enabled=true --set ingress.className=<your-controller-class-name>` to the appropriate `helm install pccs` command in [Deploy PCCS](#deploy-pccs).

    Don't have an Ingress Controller? You can install the community standard NGINX controller with the following commands:

    ```bash
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace
    ```

1. **NodePort Configure [values.yaml](https://github.com/scontain/cc-intel-pccs/blob/main/charts/pccs/values.yaml#L72-L86) to expose a static port:**

    ```bash
    service:
      type: NodePort
      nodePort: 32000
    ```

1. **Port-Forward (Development Only)** Access PCCS locally without exposing it externally. See [How to interact with](#how-to-interact-with).

### Deploy PCCS

Before deploying, **you must set your Intel DCAP API key** as an environment variable. If not provided, the PCCS service will fail to start and certificate retrieval will not work.

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

1. For a quick deployment using default settings, run (remember that DCAP is mandatory):

    ```bash
    helm install pccs ./charts/pccs --namespace pccs --create-namespace --wait \
      --set pccsConfig.apiKey=$DCAP_KEY
    ```

1. For **local environments** (e.g., `k3d`), run the following command:

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

### When using port-forward

```bash
# Terminal 1
kubectl port-forward -n pccs svc/pccs 8081:8081

# Terminal 2
curl -k https://localhost:8081/sgx/certification/v4/rootcacrl
```

### When using k3d

To allow local access using your PCCS URL, add it to `/etc/hosts`:

```bash
PCCS_URL=pccs.example.com
echo "127.0.0.1 $PCCS_URL" >> /etc/hosts
curl -k https://$PCCS_URL/sgx/certification/v4/rootcacrl
```

### PCKID Retrieval Tool

This CLI utility retrieves PCK certificate ID information from Intel SGX hardware. Given a PCCS URL and access token, it can upload that information to PCCS to register the platform for attestation.

[Intel PCKID Retrieval Tool build and usage instructions](https://github.com/intel/confidential-computing.tee.dcap/blob/main/tools/PCKRetrievalTool/README.build)

## Teardown

### Uninstall PCCS

```bash
helm uninstall pccs --namespace pccs

# Optionally, delete the namespace
kubectl delete namespace pccs
```

### Uninstall Monitoring Stack

```bash
helm uninstall kube-prometheus-stack --namespace monitoring
helm uninstall grafana --namespace monitoring
helm uninstall loki --namespace monitoring
helm uninstall blackbox-exporter --namespace monitoring

# Optionally, delete the namespace
kubectl delete namespace monitoring
```

### Uninstall Cert-Manager

```bash
helm uninstall cert-manager --namespace cert-manager

# Optionally, delete the namespace
kubectl delete namespace cert-manager
```

### Delete k3d cluster

```bash
k3d cluster delete pccs-cluster
```

## Running Tests

Copy the sample configuration and update values as needed:

```bash
cp config.env .env
# edit .env with your preferred values
sudo su
source .env
```

Then, run un all tests with:

```bash
bash tests/run-all.sh
```

Finally, to fully clean up your environment after testing, simply run:

```bash
bash ./tests/teardown.sh
```
