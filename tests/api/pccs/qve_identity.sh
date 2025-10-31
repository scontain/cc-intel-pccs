#!/bin/bash

set -euo pipefail

source ./tests/utils.sh

info "------------------------------------------------------"
info "| PCS API TESTS (/sgx/certification/v4/qve/identity) |"
info "------------------------------------------------------"

warn "Creating test set folder..."
export QVE_WORKDIR="$TMP_WORKDIR/pccs/qve_identity"
mkdir -p "$QVE_WORKDIR"
echo "Created at $QVE_WORKDIR"

METHOD="GET"
BASE_HEADER=""

ENDPOINT="sgx/certification/v4/qve/identity"
run_test "GET_QVE_IDENTITY_STANDARD" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$QVE_WORKDIR" "$BASE_HEADER"

ENDPOINT="sgx/certification/v4/qve/identity?update=standard"
run_test "GET_QVE_IDENTITY_UPDATE_STANDARD" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$QVE_WORKDIR" "$BASE_HEADER"

ENDPOINT="sgx/certification/v4/qve/identity?update=early"
run_test "GET_QVE_IDENTITY_UPDATE_EARLY" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$QVE_WORKDIR $BASE_HEADER"

ENDPOINT="sgx/certification/v4/qve/identity?update=invalid"
run_test "INVALID_QVE_IDENTITY_BAD_UPDATE" "500" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$QVE_WORKDIR $BASE_HEADER"

echo -e "${GREEN}QvE Identity tests completed successfully!${NC}"
