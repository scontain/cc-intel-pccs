#!/bin/bash

set -euo pipefail

source ./tests/utils.sh

info "------------------------------------------------"
info "| PCS API TESTS (/sgx/certification/v4/tcb)    |"
info "------------------------------------------------"

warn "Creating test set folder..."

# TMP_WORKDIR is defined earlier in run-all.sh
# shellcheck disable=SC2153
TCB_WORKDIR="$TMP_WORKDIR/pccs/tcb"
export TCB_WORKDIR

mkdir -p "$TCB_WORKDIR"
echo "Created at $TCB_WORKDIR"

METHOD="GET"
BASE_HEADER=""

VALID_FMSPC="20906EC10000"

ENDPOINT="sgx/certification/v4/tcb?fmspc=$VALID_FMSPC"
run_test "GET_TCBINFO_STANDARD" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$TCB_WORKDIR" "$BASE_HEADER"

ENDPOINT="sgx/certification/v4/tcb?fmspc=$VALID_FMSPC&update=standard"
run_test "GET_TCBINFO_UPDATE_STANDARD" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$TCB_WORKDIR" "$BASE_HEADER"

ENDPOINT="sgx/certification/v4/tcb?fmspc=$VALID_FMSPC&update=early"
run_test "GET_TCBINFO_UPDATE_EARLY" "200" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$TCB_WORKDIR" "$BASE_HEADER"

ENDPOINT="sgx/certification/v4/tcb"
run_test "INVALID_TCBINFO_MISSING_FMSPC" "400" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$TCB_WORKDIR $BASE_HEADER"

ENDPOINT="sgx/certification/v4/tcb?fmspc=INVALID"
run_test "INVALID_TCBINFO_BAD_FMSPC" "400" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$TCB_WORKDIR" "$BASE_HEADER"

ENDPOINT="sgx/certification/v4/tcb?fmspc=FFFFFFFFFFFF"
run_test "NOTFOUND_TCBINFO_UNKNOWN_FMSPC" "404" "$PCCS_URL" "$ENDPOINT" "$METHOD" "" "$TCB_WORKDIR" "$BASE_HEADER"

echo -e "${GREEN}TCB Info retrieval tests completed successfully!${NC}"
