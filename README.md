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
  -p "443:443@loadbalancer"
```

k3s ships Traefik as its ingress controller; the chart's default `ingress.className` targets it.

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

> 💡 **Tip:** If cert-manager is already installed in your cluster you do not need to reinstall it — the chart creates its own `Issuer` resources in the release namespace and uses whatever cert-manager is running. Configure how they are issued under `certManager` in `values.yaml`:
>
> ```yaml
> # values.yaml
> certManager:
>
>   # Enables automatic TLS certificate management via cert-manager
>   enabled: true
>
>   issuer:
>
>     # "selfSigned" creates a chart-owned CA that signs both the PCCS server
>     # certificate and the ingress certificate. "acme" can only issue the
>     # ingress certificate; see "Managing the certificates yourself" below.
>     type: selfSigned
>
>     # ACME directory URL (only used when type is "acme"). Let's Encrypt
>     # staging is shown; swap in the production URL for real certificates.
>     server: "https://acme-staging-v02.api.letsencrypt.org/directory"
>
>     # Contact address for expiry notices and ACME registration
>     # (only used when type is "acme").
>     email: "example@mymail.com"
> ```
>
> The `Issuer` names are derived from the release name, so nothing needs to be configured for them. Set `certManager.enabled: false` only if you intend to supply every certificate yourself.

Run the following commands:

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager --set installCRDs=true \
  --version v1.18.2 --namespace cert-manager --create-namespace

# Wait for cert-manager to be ready
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=120s
```

### Exposing PCCS (Important)

This chart does not install an ingress controller. If your cluster already provides one (traefik, nginx, etc.), enable ingress and set the correct one:

```bash
helm install ... --set ingress.enabled=true --set ingress.className=<controller>
```

PCCS serves HTTPS only, so the controller must speak TLS to the backend. The chart renders that configuration for `traefik` (the default; a `ServersTransport` plus Service annotations, verifying the backend against the chart's CA) and for `nginx` (`backend-protocol: HTTPS`). For any other controller, pass its equivalent through `ingress.annotations`.

> ⚠️ **Upgrading from chart < 0.2.0:** the default `ingress.className` changed from `nginx` to `traefik` — if you use ingress-nginx, set `--set ingress.className=nginx` explicitly. The ingress certificate is now the one this chart requests (`<release>-ingress-tls`) rather than one cert-manager created from a `cert-manager.io/issuer` annotation, so the leftover `ingress-tls` secret and its Certificate can be deleted.

> ⚠️ **Backend certificate trust:** with the default `certManager.issuer.type: selfSigned`, the chart points the controller at its own CA, so the ingress verifies the PCCS certificate and nothing further is needed. `certManager.issuer.type: acme` cannot issue the PCCS server certificate at all — no public ACME CA signs the in-cluster names (`pccs.<namespace>.svc`) it needs — so those deployments must supply it through `tls.serverSecretName` and then either `tls.caSecretName` or `--set ingress.traefik.insecureSkipVerify=true`. When no CA is available the chart refuses to render rather than proxy to an unverified backend.

For more configuration details, see the ingress section in `values.yaml`. If your cluster does not have an ingress controller installed, choose one of the following ways to expose the PCCS service:

1. Install an ingress controller (recommended)

    Example with Traefik. Remember to use the flags above when installing PCCS:

    ```bash
    helm repo add traefik https://traefik.github.io/charts
    helm install traefik traefik/traefik --namespace traefik --create-namespace
    ```

1. Expose PCCS using NodePort

    ```bash
    service:
      type: NodePort
      nodePort: 32000
    ```

1. Development only – port-forward after deploying PCCS

    ```bash
    kubectl port-forward -n pccs svc/pccs 8081:8081
    ```

### Managing the certificates yourself

By default cert-manager issues everything: a self-signed CA, the PCCS server certificate (`<release>-tls`, mounted into the pod) and the ingress certificate (`<release>-ingress-tls`). With `certManager.enabled: false` the chart issues nothing and you supply the secrets instead. PCCS serves HTTPS only, so a server certificate is always required:

```bash
helm install ... \
  --set certManager.enabled=false \
  --set tls.serverSecretName=my-pccs-tls \
  --set tls.caSecretName=my-ca \
  --set ingress.tlsSecretName=my-ingress-tls
```

* `tls.serverSecretName` — holds `tls.crt` and `tls.key` for the PCCS listener. It must carry `<release>.<namespace>.svc` among its Subject Alternative Names: that is the name an ingress controller verifies when it opens the backend connection.
* `tls.caSecretName` — holds the `ca.crt` of the CA that signed the above, so the ingress controller can verify it. Alternatively skip verification with `ingress.traefik.insecureSkipVerify=true`.
* `ingress.tlsSecretName` — the certificate the controller serves for `ingress.host`. Only needed when `ingress.enabled=true`.

If one of the required secrets is not set, the chart fails with a message naming it instead of creating a pod that waits forever for a Secret nobody creates.

These values also work one at a time with `certManager.enabled: true`: setting `tls.serverSecretName` or `ingress.tlsSecretName` stops the chart requesting the corresponding `Certificate`, so cert-manager keeps issuing the other one. `tls.serverSecretName` on its own means the chart no longer has a CA of its own either, so pair it with `tls.caSecretName`.

#### Certificate renewal

PCCS picks up a renewed server certificate without a restart: the Secret is mounted as a directory, which the kubelet refreshes when the Secret changes, and PCCS re-reads the key and certificate every 60 seconds. A renewal therefore reaches every pod within about two minutes. This applies to your own `tls.serverSecretName` as well, so rotate it by updating the Secret in place.

> 💡 **Tip:** The re-read interval is configurable through `pccsConfig.tlsReloadIntervalSeconds` (default `60`; `0` reads the certificate only at startup, so a renewal then needs a pod restart):
>
> ```bash
> helm upgrade ... --set pccsConfig.tlsReloadIntervalSeconds=300
> ```
>
> PCCS reads this setting at startup, so run `kubectl rollout restart statefulset/<release> -n <namespace>` after changing it on an existing release.

The chart's own CA is valid for ten years and is renewed on the same private key, so certificates it signed earlier keep verifying across a renewal. If you replace the CA behind `tls.caSecretName` with one on a new key, put both the old and the new CA certificate in its `ca.crt` until every pod serves a certificate signed by the new one; otherwise the ingress rejects the pods still on the old certificate.

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

> ⚠️ **Upgrading to PCCS 1.27:** The chart defaults to the versioned image built from Intel's `DCAP_1.27` release. Back up the PCCS database PVC before upgrading because PCCS runs schema migrations during startup. The image carries the patches in `container/pccs/patches` (health endpoints, and reloading a renewed HTTPS certificate) until they are accepted upstream.

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

The probe in `monitoring/prometheus-probe.yaml` targets the PCCS Service directly (`https://pccs.pccs.svc.cluster.local:8081`); change the release name, namespace or port there if yours differ.

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
source .env
```

The scripts run as a regular user and call `sudo` only where needed (package
installation and the `/etc/hosts` entry for `PCCS_URL`).

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
1. On an SGX host only: installs PCKIDRetrievalTool and tests platform
   registration and package management
1. Runs PCCS API tests
1. Renews the PCCS server certificate and checks that every pod serves the
   new one, without restarting, and that the ingress still reaches PCCS

The registration tests run only when an SGX device node exists (`/dev/sgx`,
`/dev/sgx_enclave` or `/dev/sgx_provision`); otherwise they are skipped with a
warning. Set
`REQUIRE_SGX=true` to fail instead of skipping. PCKIDRetrievalTool needs
access to `/dev/sgx_provision`, which is root-only unless your user is in the
`sgx_prv` group, so it is run through `sudo` otherwise.

The cluster binds host ports 80 and 443, so no other k3d cluster (or anything
else) may be listening on them.

The console shows one line per setup step and per test. Full output is kept
under the run's working directory `tests/tmp/tmp.*/`:

* `logs/<step>.log` for each install, k3d, helm and rollout step; a failing
  step also prints its last 40 lines
* `pccs/<endpoint>/TEST_<name>/` for each test's response header and body; a
  failing test also prints them
* `logs/diagnostics/` for full pod logs, events and Traefik logs when a run
  fails after the cluster is up; the console shows a filtered summary

In CI, `tests/tmp/` (without the kubeconfig) is uploaded as the
`integration-test-output` artifact.

### CI

The integration job in `.github/workflows/pr.yml` runs on `ubuntu-latest`,
which has no SGX device, so CI runs the PCCS API tests and skips the
registration tests. Run `tests/run-all.sh` on an SGX host with
`REQUIRE_SGX=true` to cover them.

### Teardown

To fully clean up your environment after testing, simply run:

```bash
bash ./tests/teardown.sh
```

This script will:

1. Clean up any `/etc/hosts` entries related to `$PCCS_URL`.
1. Delete the **k3d cluster**.
