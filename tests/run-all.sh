#!/usr/bin/env bash

set -Eeuo pipefail

source ./tests/utils.sh

on_exit() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ -s "${KUBECONFIG:-}" ]; then
    dump_diagnostics
  fi
}
trap on_exit EXIT

info "----------------------------------------------------"
info "| RUN-ALL: Checking required environment variables |"
info "----------------------------------------------------"

check_required_envs

# Optional: REQUIRE_SGX=true makes a host without SGX fail here instead of
# skipping the PCS registration tests. CI (ubuntu-latest, no SGX) leaves it
# unset.
if [ "${REQUIRE_SGX:-false}" = "true" ] && ! sgx_device_present; then
  error_exit "REQUIRE_SGX=true but no SGX device found on $(hostname)"
fi

echo "Creating temporary working directory under tests/tmp..."

mkdir -p tests/tmp

TMP_WORKDIR=$(mktemp -d -p tests/tmp)
export TMP_WORKDIR

echo -e "${GREEN}Temporary working directory created at: $TMP_WORKDIR${NC}"

info "------------------------------"
info "| RUN-ALL: SETUP ENVIRONMENT |"
info "------------------------------"

source ./tests/setup-environment.sh

if sgx_device_present; then

  info "------------------------------"
  info "| RUN-ALL: RUN PCS API TESTS |"
  info "------------------------------"

  warn "Installing PCKIDRetrievalTool..."
  curl -fsS https://download.01.org/intel-sgx/latest/dcap-latest/linux/distro/ubuntu24.04-server/PCKIDRetrievalTool_v1.27.101.1.tar.gz \
    -o "$TMP_WORKDIR/PCKIDRetrievalTool.tar.gz"

  tar -xzf "$TMP_WORKDIR/PCKIDRetrievalTool.tar.gz" -C "$TMP_WORKDIR"
  mv "$TMP_WORKDIR/PCKIDRetrievalTool_v1.27.101.1" "$TMP_WORKDIR/PCKIDRetrievalTool"
  echo -e "${GREEN}Done.${NC}"

  source ./tests/api/pcs/register.sh
  source ./tests/api/pcs/package.sh

else
  warn "SGX not found, skipping register platform and add package tests"
fi

info "-------------------------------"
info "| RUN-ALL: RUN PCCS API TESTS |"
info "-------------------------------"

source ./tests/api/pccs/appraisal_policy.sh
source ./tests/api/pccs/crl.sh
source ./tests/api/pccs/pckcert.sh
source ./tests/api/pccs/pckcrl.sh
source ./tests/api/pccs/platform_collateral.sh
source ./tests/api/pccs/platforms.sh
source ./tests/api/pccs/qe_identity.sh
source ./tests/api/pccs/qve_identity.sh
source ./tests/api/pccs/refresh.sh
source ./tests/api/pccs/rootcacrl.sh
source ./tests/api/pccs/tcb.sh

info "-----------------------------"
info "| RUN-ALL: RUN TLS TESTS    |"
info "-----------------------------"

source ./tests/tls/cert_renewal.sh

info "----------------------------"
info "| CI FINISHED SUCCESSFULLY |"
info "----------------------------"
