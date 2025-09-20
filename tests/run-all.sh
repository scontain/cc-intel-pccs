#!/usr/bin/env bash

set -euo pipefail

source ./tests/utils.sh

info "----------------------------------------------------"
info "| RUN-ALL: Checking required environment variables |"
info "----------------------------------------------------"

check_required_envs

echo "Creating temporary working directory under tests/tmp..."

mkdir -p tests/tmp
export TMP_WORKDIR=$(mktemp -d -p tests/tmp)

echo -e "${GREEN}Temporary working directory created at: $TMP_WORKDIR${NC}"

info "------------------------------"
info "| RUN-ALL: SETUP ENVIRONMENT |"
info "------------------------------"

source ./tests/setup-environment.sh

if [ -e /dev/sgx ] || [ -e /dev/sgx_enclave ] || [ -e /dev/sgx_provision ]; then

  info "------------------------------"
  info "| RUN-ALL: RUN PCS API TESTS |"
  info "------------------------------"

  warn "Installing PCKIDRetrievalTool..."
  curl --fail https://download.01.org/intel-sgx/latest/dcap-latest/linux/distro/ubuntu24.04-server/PCKIDRetrievalTool_v1.23.100.0.tar.gz \
    -o "$TMP_WORKDIR/PCKIDRetrievalTool.tar.gz"

  tar -xzf "$TMP_WORKDIR/PCKIDRetrievalTool.tar.gz" -C "$TMP_WORKDIR"
  mv "$TMP_WORKDIR/PCKIDRetrievalTool_v1.23.100.0" "$TMP_WORKDIR/PCKIDRetrievalTool"
  echo -e "${GREEN}Done.${NC}"

  source ./tests/api/pcs/register.sh
  source ./tests/api/pcs/package.sh

else
  warn "SGX not found, skipping register platform and add package tests" 
fi

info "----------------------------"
info "| CI FINISHED SUCCESSFULLY |"
info "----------------------------"
