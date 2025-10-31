#!/bin/bash

set -euo pipefail

source ./tests/utils.sh

info "-------------------------------------------------"
info "| PCS API TESTS (/sgx/certification/v4/rootcacrl) |"
info "-------------------------------------------------"

warn "Creating test set folder..."
export ROOTCACRL_WORKDIR="$TMP_WORKDIR/pccs/rootcacrl"
mkdir -p "$ROOTCACRL_WORKDIR"
echo "Created at $ROOTCACRL_WORKDIR"

METHOD="GET"
BASE_HEADER=""

ENDPOINT="sgx/certification/v4/rootcacrl"
run_test "GET_ROOTCACRL" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$ROOTCACRL_WORKDIR" "${BASE_HEADER[@]}"

echo -e "${GREEN}Root CA CRL tests completed successfully!${NC}"
