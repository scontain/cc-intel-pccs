#!/bin/bash

set -euo pipefail

source ./tests/utils.sh

info "--------------------------------------------------------------"
info "| PCS API TESTS (/sgx/certification/v4/platformcollateral)   |"
info "--------------------------------------------------------------"

warn "Creating test set folder..."
export COLLATERAL_WORKDIR="$TMP_WORKDIR/pccs/platformcollateral"
mkdir -p "$COLLATERAL_WORKDIR"
echo "Created at $COLLATERAL_WORKDIR"

METHOD_PUT="PUT"
ENDPOINT_BASE="sgx/certification/v4/platformcollateral"

BASE_HEADER=(-H "Content-Type: application/json" -H "admin-token: $PCCS_ADMIN_TOKEN")
BASE_HEADER_INVALID=(-H "Content-Type: application/json" -H "admin-token: INVALIDTOKEN")

VALID_BODY_FILE="$COLLATERAL_WORKDIR/sample_collateral_valid.json"
cat > "$VALID_BODY_FILE" <<EOF
{
  "platforms": [
    {
      "qe_id": "0011",
      "pce_id": "0002",
      "cpu_svn": "0102030405060708090a0b0c0d0e0f10",
      "pce_svn": "0001",
      "enc_ppid": "ABCD1234",
      "platform_manifest": "manifest"
    }
  ],
  "collaterals": {
    "version": "4",
    "pck_certs": [
      {
        "qe_id": "0011",
        "pce_id": "0002",
        "enc_ppid": "ABCD1234",
        "platform_manifest": "manifest",
        "certs": []
      }
    ],
    "tcbinfos": [
      {
        "fmspc": "20906EC10000",
        "sgx_tcbnfo": {},
        "tdx_tcbnfo": {}
      }
    ],
    "pckcacrl": "dummy",
    "qeidentity": "dummy",
    "tdqeidentity": "dummy",
    "qveidentity": "dummy",
    "certificates": {
      "SGX-PCK-Certificate-Issuer-Chain": "dummy",
      "TCB-Info-Issuer-Chain": "dummy",
      "SGX-Enclave-Identity-Issuer-Chain": "dummy"
    },
    "rootcacrl": "dummy"
  }
}
EOF

INVALID_BODY_FILE="$COLLATERAL_WORKDIR/sample_collateral_invalid.json"
echo "{ invalid json }" > "$INVALID_BODY_FILE"

run_test "PUT_PLATFORMCOLLATERAL_BADTOKEN" "401" "$PCCS_URL" "$ENDPOINT_BASE?platform_count=1" "$METHOD_PUT" "$VALID_BODY_FILE" "$COLLATERAL_WORKDIR" "${BASE_HEADER_INVALID[@]}"
run_test "PUT_PLATFORMCOLLATERAL_INVALID_BODY" "400" "$PCCS_URL" "$ENDPOINT_BASE?platform_count=1" "$METHOD_PUT" "$INVALID_BODY_FILE" "$COLLATERAL_WORKDIR" "${BASE_HEADER[@]}"
run_test "PUT_PLATFORMCOLLATERAL_MISSING_COUNT" "400" "$PCCS_URL" "$ENDPOINT_BASE" "$METHOD_PUT" "$VALID_BODY_FILE" "$COLLATERAL_WORKDIR" "${BASE_HEADER[@]}"

echo -e "${GREEN}Platform collateral PUT tests completed successfully!${NC}"
