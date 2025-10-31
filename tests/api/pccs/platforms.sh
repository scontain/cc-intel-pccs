#!/bin/bash

set -euo pipefail

source ./tests/utils.sh

info "---------------------------------------------------"
info "| PCS API TESTS (/sgx/certification/v4/platforms) |"
info "---------------------------------------------------"

warn "Creating test set folder..."
export PLAT_WORKDIR="$TMP_WORKDIR/pccs/platforms"
mkdir -p "$PLAT_WORKDIR"
echo "Created at $PLAT_WORKDIR"

METHOD_GET="GET"
METHOD_POST="POST"
ADMIN_HEADER=(-H "admin-token: $PCCS_ADMIN_TOKEN")
USER_HEADER=(-H "user-token: $PCCS_USER_TOKEN")
HEADER_MISSING=""

ENDPOINT="sgx/certification/v4/platforms"
run_test "GET_PLATFORMS_ALL" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD_GET" "" "$PLAT_WORKDIR" "${ADMIN_HEADER[@]}"

VALID_FMSPC="20906EC10000"
ENDPOINT="sgx/certification/v4/platforms?fmspc=$VALID_FMSPC"
run_test "GET_PLATFORMS_SINGLE" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD_GET" "" "$PLAT_WORKDIR" "${ADMIN_HEADER[@]}"

FMSPC_LIST="20906EC10000,FFFFFFFFFFFF"
ENDPOINT="sgx/certification/v4/platforms?fmspc=$FMSPC_LIST"
run_test "GET_PLATFORMS_MULTIPLE" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD_GET" "" "$PLAT_WORKDIR" "${ADMIN_HEADER[@]}"

ENDPOINT="sgx/certification/v4/platforms"
run_test "INVALID_PLATFORMS_NO_ADMIN_TOKEN" "401" "$PCCS_URL" "$ENDPOINT" "$METHOD_GET" "" "$PLAT_WORKDIR" "${HEADER_MISSING[@]}"

VALID_POST_FILE="$PLAT_WORKDIR/sample_platform_valid.json"
cat > "$VALID_POST_FILE" <<EOF
{
  "qe_id": "0011223344556677",
  "pce_id": "0002",
  "cpu_svn": "0102030405060708090a0b0c0d0e0f10",
  "pce_svn": "0001",
  "enc_ppid": "ABCD1234",
  "platform_manifest": "DEADBEEF"
}
EOF

INVALID_POST_FILE="$PLAT_WORKDIR/sample_platform_invalid.json"
echo "{ invalid json }" > "$INVALID_POST_FILE"

ENDPOINT="sgx/certification/v4/platforms?fmspc=$VALID_FMSPC"

run_test "POST_PLATFORM_INVALID_BODY" "400" "$PCCS_URL" "$ENDPOINT" "$METHOD_POST" "$INVALID_POST_FILE" "$PLAT_WORKDIR" "${USER_HEADER[@]}"
run_test "POST_PLATFORM_NO_TOKEN" "401" "$PCCS_URL" "$ENDPOINT" "$METHOD_POST" "$VALID_POST_FILE" "$PLAT_WORKDIR" -H "Content-Type: application/json"
run_test "POST_PLATFORM_BADTOKEN" "401" "$PCCS_URL" "$ENDPOINT" "$METHOD_POST" "$VALID_POST_FILE" "$PLAT_WORKDIR" -H "user-token: INVALIDTOKEN"

echo -e "${GREEN}Platform IDs GET/POST tests completed successfully!${NC}"
