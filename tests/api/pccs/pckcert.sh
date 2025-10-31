#!/bin/bash

set -euo pipefail

source ./tests/utils.sh

info "-------------------------------------------------"
info "| PCS API TESTS (/sgx/certification/v4/pckcert) |"
info "-------------------------------------------------"

warn "Creating test set folder..."
export REGISTER_WORKDIR="$TMP_WORKDIR/pcs/register"
export PCKCERT_WORKDIR="$TMP_WORKDIR/pccs/pckcert"
mkdir -p "$PCKCERT_WORKDIR"
echo "Created at $PCKCERT_WORKDIR"

METHOD="GET"
BASE_HEADER=""

ENDPOINT="sgx/certification/v4/pckcert"
run_test "INVALID_PCKCERT_MISSING_PARAMS" "400" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$PCKCERT_WORKDIR" "${BASE_HEADER[@]}"

ENDPOINT="sgx/certification/v4/pckcert?encrypted_ppid=1234&cpusvn=00000000000000000000000000000000&pcesvn=0000&pceid=0000"
run_test "INVALID_PCKCERT_BAD_PPID" "400" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$PCKCERT_WORKDIR" "${BASE_HEADER[@]}"

ENDPOINT="sgx/certification/v4/pckcert?encrypted_ppid=$(printf 'A%.0s' {1..768})&cpusvn=BAD&pcesvn=0000&pceid=0000"
run_test "INVALID_PCKCERT_BAD_CPUSVN" "400" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$PCKCERT_WORKDIR" "${BASE_HEADER[@]}"

ENDPOINT="sgx/certification/v4/pckcert?encrypted_ppid=$(printf 'A%.0s' {1..768})&cpusvn=00000000000000000000000000000000&pcesvn=ZZZZ&pceid=0000"
run_test "INVALID_PCKCERT_BAD_PCESVN" "400" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$PCKCERT_WORKDIR" "${BASE_HEADER[@]}"

ENDPOINT="sgx/certification/v4/pckcert?encrypted_ppid=$(printf 'A%.0s' {1..768})&cpusvn=00000000000000000000000000000000&pcesvn=0000&pceid=GGGG"
run_test "INVALID_PCKCERT_BAD_PCEID" "400" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$PCKCERT_WORKDIR" "${BASE_HEADER[@]}"

echo -e "${GREEN}PCK Certificate tests completed!${NC}"
