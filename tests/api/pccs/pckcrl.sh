#!/bin/bash

set -euo pipefail

source ./tests/utils.sh

info "-------------------------------------------------"
info "| PCS API TESTS (/sgx/certification/v4/pckcrl) |"
info "-------------------------------------------------"

warn "Creating test set folder..."
export PCKCRL_WORKDIR="$TMP_WORKDIR/pccs/pckcrl"
mkdir -p "$PCKCRL_WORKDIR"
echo "Created at $PCKCRL_WORKDIR"

METHOD="GET"
BASE_HEADER=""

ENDPOINT="sgx/certification/v4/pckcrl?ca=processor"
run_test "GET_PCKCRL_PROCESSOR_PEM" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$PCKCRL_WORKDIR" "${BASE_HEADER[@]}"

ENDPOINT="sgx/certification/v4/pckcrl?ca=platform"
run_test "GET_PCKCRL_PLATFORM_PEM" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$PCKCRL_WORKDIR" "${BASE_HEADER[@]}"

ENDPOINT="sgx/certification/v4/pckcrl?ca=processor&encoding=der"
run_test "GET_PCKCRL_PROCESSOR_DER" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$PCKCRL_WORKDIR" "${BASE_HEADER[@]}"

ENDPOINT="sgx/certification/v4/pckcrl?ca=platform&encoding=der"
run_test "GET_PCKCRL_PLATFORM_DER" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$PCKCRL_WORKDIR" "${BASE_HEADER[@]}"

ENDPOINT="sgx/certification/v4/pckcrl"
run_test "INVALID_PCKCRL_MISSING_CA" "400" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$PCKCRL_WORKDIR" "${BASE_HEADER[@]}"

ENDPOINT="sgx/certification/v4/pckcrl?ca=invalidca"
run_test "INVALID_PCKCRL_BAD_CA" "400" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$PCKCRL_WORKDIR" "${BASE_HEADER[@]}"

echo -e "${GREEN}PCK CRL tests completed successfully!${NC}"
