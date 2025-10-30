#!/bin/bash

set -euo pipefail

source ./tests/utils.sh

info "---------------------------------------------------------"
info "| PCS API TESTS (/sgx/certification/v4/appraisalpolicy) |"
info "---------------------------------------------------------"

warn "Creating test set folder..."
export APPRAISAL_WORKDIR="$TMP_WORKDIR/pccs/appraisalpolicy"
mkdir -p "$APPRAISAL_WORKDIR"
echo "Created at $APPRAISAL_WORKDIR"

METHOD_GET="GET"
METHOD_PUT="PUT"
BASE_HEADER=(-H "admin-token: $PCCS_ADMIN_TOKEN")

ENDPOINT="sgx/certification/v4/appraisalpolicy"

POLICY_INVALID_FILE="$APPRAISAL_WORKDIR/sample_policy_invalid.json"
echo "{ invalid json }" > "$POLICY_INVALID_FILE"

run_test "PUT_APPRAISAL_POLICY_INVALID" "400" "$PCCS_URL" "$ENDPOINT" "$METHOD_PUT" "$POLICY_INVALID_FILE" "$APPRAISAL_WORKDIR" "${BASE_HEADER[@]}"

BASE_HEADER_INVALID=(-H "admin-token: INVALIDTOKEN")
run_test "PUT_APPRAISAL_POLICY_BADTOKEN" "401" "$PCCS_URL" "$ENDPOINT" "$METHOD_PUT" "$POLICY_INVALID_FILE" "$APPRAISAL_WORKDIR" "${BASE_HEADER_INVALID[@]}"

ENDPOINT="sgx/certification/v4/appraisalpolicy?fmspc=123456789ABCDE"
run_test "GET_APPRAISAL_POLICY_INVALID" "400" "$PCCS_URL" "$ENDPOINT" "$METHOD_GET" "" "$APPRAISAL_WORKDIR" "${BASE_HEADER[@]}"

ENDPOINT="sgx/certification/v4/appraisalpolicy?fmspc=FFFFFFFFFFFF"
run_test "GET_APPRAISAL_POLICY_UNKNOWN" "404" "$PCCS_URL" "$ENDPOINT" "$METHOD_GET" "" "$APPRAISAL_WORKDIR" "${BASE_HEADER[@]}"

echo -e "${GREEN}Appraisal policy GET/PUT tests completed successfully!${NC}"
