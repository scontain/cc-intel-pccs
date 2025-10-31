#!/bin/bash

set -euo pipefail

source ./tests/utils.sh

info "---------------------------------------------"
info "| PCS API TESTS (/sgx/certification/v4/crl) |"
info "---------------------------------------------"

warn "Creating test set folder..."
export CRL_WORKDIR="$TMP_WORKDIR/pccs/crl"
mkdir -p "$CRL_WORKDIR"
echo "Created at $CRL_WORKDIR"

METHOD="GET"
BASE_HEADER=""

VALID_CRL_URI="https://certificates.trustedservices.intel.com/IntelSGXRootCA.der"
ENDPOINT="sgx/certification/v4/crl?uri=$VALID_CRL_URI"
run_test "GET_CRL_ROOTCA" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$CRL_WORKDIR" "${BASE_HEADER[@]}"

ENDPOINT="sgx/certification/v4/crl"
run_test "INVALID_CRL_MISSING_URI" "400" "$PCCS_URL" "$ENDPOINT $METHOD" "" "$CRL_WORKDIR" "${BASE_HEADER[@]}"

INVALID_CRL_URI="not-a-valid-url"
ENDPOINT="sgx/certification/v4/crl?uri=$INVALID_CRL_URI"
run_test "INVALID_CRL_BAD_URI" "400" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$CRL_WORKDIR" "${BASE_HEADER[@]}"

NONEXISTENT_CRL_URI="https://certificates.trustedservices.intel.com/nonexistent.crl"
ENDPOINT="sgx/certification/v4/crl?uri=$NONEXISTENT_CRL_URI"
run_test "NONEXISTENT_CRL" "400" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$CRL_WORKDIR" "${BASE_HEADER[@]}"

echo -e "${GREEN}CRL tests completed successfully!${NC}"
