#!/bin/bash

set -euo pipefail

source ./tests/utils.sh
# https://api.portal.trustedservices.intel.com/content/documentation.html#register-platform

info "----------------------------------------------------"
info "| PCS API TESTS (/api/sgx/registation/v1/platform) |"
info "----------------------------------------------------"

warn "Creating test set folder..."
export REGISTER_WORKDIR="$TMP_WORKDIR/pcs/register"
mkdir -p "$REGISTER_WORKDIR"
echo "Created at $REGISTER_WORKDIR"
echo

BASE_URL="api.trustedservices.intel.com"
ENDPOINT="sgx/registration/v1/platform"
METHOD="POST"
BASE_HEADER=(-H "Content-Type: application/octet-stream")

warn "Retrieving platform manifest ..."

"$TMP_WORKDIR"/PCKIDRetrievalTool/PCKIDRetrievalTool \
  -f "$REGISTER_WORKDIR"/platform_manifest \
  -url "$PCCS_URL" \
  -use_secure_cert false \
  -user_token "$PCCS_USER_TOKEN"

echo
warn "Manifest:"
cat "$REGISTER_WORKDIR/platform_manifest"
echo -e "\n${GREEN}Done.${NC}\n"

echo "Extracting Platform ID..."
PLATFORM_ID="$(csvtool col 6 "$REGISTER_WORKDIR"/platform_manifest)"
export PLATFORM_ID

if [[ -n "$PLATFORM_ID" ]]; then
  echo -e "${GREEN}Done.${NC}"
  echo "$PLATFORM_ID" | xxd -r -p - "$REGISTER_WORKDIR/platform_manifest.bin"

  run_test "VALID_REGISTER" "201" "$BASE_URL" "$ENDPOINT" $METHOD"$REGISTER_WORKDIR/platform_manifest.bin" "$REGISTER_WORKDIR" "${BASE_HEADER[@]}"
else
  echo "Skipping test (VALID_REGISTER): No platform ID available."
fi

xxd -r -p < "$REGISTER_WORKDIR/platform_manifest" > "$REGISTER_WORKDIR/bad_syntax.bin"
run_test "BAD_SYNTAX" "400" "$BASE_URL" "$ENDPOINT" "$METHOD" "$REGISTER_WORKDIR/bad_syntax.bin" "$REGISTER_WORKDIR" "${BASE_HEADER[@]}"

echo -e "${GREEN}Registration tests completed successfully!${NC}"
