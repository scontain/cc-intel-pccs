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

### Deploy PCCS

First, configure all parameters marked with "!REQUIRED" in `charts/pccs/values.yaml`. Then, deploy PCCS using Helm:

```bash
helm install pccs ./charts/pccs --namespace pccs --create-namespace --wait
```

This command installs PCCS in the `pccs` namespace. If the namespace does not exist, it will be created automatically.

## Interact with

To interact with PCCS locally, use kubectl `port-forward` and `curl`:

```bash
kubectl port-forward -n pccs pod/pccs-0 8081:8081 &
curl -k https://127.0.0.1:8081/sgx/certification/v4/rootcacrl
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
