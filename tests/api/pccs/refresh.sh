#!/bin/bash

set -euo pipefail

source ./tests/utils.sh

info "-------------------------------------------------"
info "| PCS API TESTS (/sgx/certification/v4/refresh) |"
info "-------------------------------------------------"

warn "Creating test set folder..."
export REFRESH_WORKDIR="$TMP_WORKDIR/pccs/refresh"
mkdir -p "$REFRESH_WORKDIR"
echo "Created at $REFRESH_WORKDIR"

METHOD="POST"
BASE_HEADER=(-H "admin-token: $PCCS_ADMIN_TOKEN")

ENDPOINT="sgx/certification/v4/refresh"
run_test "REFRESH_DEFAULT" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$REFRESH_WORKDIR" "${BASE_HEADER[@]}"

ENDPOINT="sgx/certification/v4/refresh?type=certs"
run_test "REFRESH_CERTS_ALL" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$REFRESH_WORKDIR" "${BASE_HEADER[@]}"

VALID_FMSPCS="20906EC10000,112233445566"
ENDPOINT="sgx/certification/v4/refresh?type=certs&fmspc=$VALID_FMSPCS"
run_test "REFRESH_CERTS_SPECIFIC" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$REFRESH_WORKDIR" "${BASE_HEADER[@]}"

BASE_HEADER_INVALID=(-H "admin-token: INVALIDTOKEN")
ENDPOINT="sgx/certification/v4/refresh"
run_test "REFRESH_INVALID_TOKEN" "401" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$REFRESH_WORKDIR" "${BASE_HEADER_INVALID[@]}"

echo -e "${GREEN}Refresh API tests completed successfully!${NC}"
