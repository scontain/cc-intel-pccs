#!/bin/bash

set -euo pipefail

source ./tests/utils.sh
# https://api.portal.trustedservices.intel.com/content/documentation.html#add-package

info "-------------------------------------------------"
info "| PCS API TESTS (/api/sgx/registation/v1/package) |"
info "-------------------------------------------------"

warn "Creating test set folder..."
export PACKAGE_WORKDIR="$TMP_WORKDIR/pcs/package"
mkdir -p "$PACKAGE_WORKDIR"
echo "Created at $PACKAGE_WORKDIR"

BASE_URL="api.trustedservices.intel.com"
ENDPOINT="sgx/registration/v1/package"
METHOD="POST"
BASE_HEADER=(-H "Content-Type: application/octet-stream")

warn "Retrieving add package ..."

"$TMP_WORKDIR"/PCKIDRetrievalTool/PCKIDRetrievalTool \
  -f "$PACKAGE_WORKDIR/add_package" \
  -url "$PCCS_URL" \
  -use_secure_cert false \
  -user_token "$PCCS_USER_TOKEN"

# Expecting 400 because this test attempts to add a package that is already registered (during register.sh)
if [[ -n "$PLATFORM_ID" ]]; then
  run_test "INVALID_ADD_PACKAGE_DUPLICATE" "400" "$BASE_URL" "$ENDPOINT" "$METHOD" "$PACKAGE_WORKDIR/sample_add_request.bin" "$PACKAGE_WORKDIR" "${BASE_HEADER[@]}"
else
  echo "Skipping test (INVALID_ADD_PACKAGE_DUPLICATE): No platform ID available."
fi

echo "Invalid binary data for testing" > "$PACKAGE_WORKDIR/malformed_request.bin"
run_test "ADD_PACKAGE_INVALID_HEADER" "401" "$BASE_URL" "$ENDPOINT" "$METHOD" "$PACKAGE_WORKDIR/malformed_request.bin" "$PACKAGE_WORKDIR" "${BASE_HEADER[@]}"

echo -e "${GREEN}Package addition tests completed successfully!${NC}"
