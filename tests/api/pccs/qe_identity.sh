#!/bin/bash

set -euo pipefail

source ./tests/utils.sh

info "-----------------------------------------------------"
info "| PCS API TESTS (/sgx/certification/v4/qe/identity) |"
info "-----------------------------------------------------"

warn "Creating test set folder..."
export QE_IDENTITY_WORKDIR="$TMP_WORKDIR/pccs/qe_identity"
mkdir -p "$QE_IDENTITY_WORKDIR"
echo "Created at $QE_IDENTITY_WORKDIR"

METHOD="GET"
BASE_HEADER=""

ENDPOINT="sgx/certification/v4/qe/identity?update=standard"
run_test "GET_QE_IDENTITY_STANDARD" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$QE_IDENTITY_WORKDIR" "${BASE_HEADER[@]}"

ENDPOINT="sgx/certification/v4/qe/identity?update=early"
run_test "GET_QE_IDENTITY_EARLY" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$QE_IDENTITY_WORKDIR" "${BASE_HEADER[@]}"

VALID_TCB_EVAL_NUM="12"
ENDPOINT="sgx/certification/v4/qe/identity?tcbEvaluationDataNumber=$VALID_TCB_EVAL_NUM"
run_test "GET_QE_IDENTITY_TCB_NUM" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$QE_IDENTITY_WORKDIR" "${BASE_HEADER[@]}"

ENDPOINT="sgx/certification/v4/qe/identity?update=invalidvalue"
run_test "INVALID_QE_IDENTITY_BAD_UPDATE" "500" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$QE_IDENTITY_WORKDIR" "${BASE_HEADER[@]}"

echo -e "${GREEN}QE Identity tests completed successfully!${NC}"
