#!/usr/bin/env bash

set -euo pipefail

# --------------------
# Colors
# --------------------
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --------------------
# Logging helpers
# --------------------
info() {
  echo -e "${CYAN}$1${NC}"
}

warn() {
  echo -e "${YELLOW}$1${NC}"
}

error_exit() {
  echo -e "${RED}$1${NC}"
  exit 1
}

# --------------------
# Test functions
# --------------------

check_required_envs () {
  local MISSING_VARS=()

  local REQUIRED_ENVS=($(grep -E '^\s*export\s+[A-Za-z_][A-Za-z0-9_]*' ./config.env \
  | sed -E 's/^\s*export\s+([A-Za-z_][A-Za-z0-9_]*).*/\1/'))

  for ENV_VAR in "${REQUIRED_ENVS[@]}"; do
    if [ -z "${!ENV_VAR:-}" ]; then
      MISSING_VARS+=("$ENV_VAR")
    fi
  done

  if [ "${#MISSING_VARS[@]}" -eq 0 ]; then
    echo -e "${GREEN}All required environment variables are set${NC}"
  else
    error_exit "Missing required environment variable(s): ${MISSING_VARS[*]}"
  fi
}

run_test() {
  local TEST_NAME="$1"
  local EXPECTED_STATUS="$2"
  local BASE_URL="$3"
  local ENDPOINT="$4"
  local METHOD="$5"
  local REQUEST_BODY="$6"
  local WORKDIR="$7"
  shift 7
  local REQUEST_HEADER=("$@")

  echo
  warn ">>> Running test: $TEST_NAME (expect HTTP $EXPECTED_STATUS)"

  local TEST_DIR="$WORKDIR/TEST_${TEST_NAME}"
  mkdir -p "$TEST_DIR"

  local RESPONSE_BODY="$TEST_DIR/response_body.txt"
  local RESPONSE_HEADER="$TEST_DIR/response_header.txt"

  local CURL_ARGS=("${REQUEST_HEADER[@]}" -X "$METHOD" -k -s --show-error -w "%{http_code}" -o "$RESPONSE_BODY" -D "$RESPONSE_HEADER")

  if [[ -n "$REQUEST_BODY" ]]; then
    CURL_ARGS+=(--data-binary @"$REQUEST_BODY")
  fi

  local STATUS_CODE
  STATUS_CODE=$(curl "${CURL_ARGS[@]}" "$BASE_URL/$ENDPOINT")

  if [[ "$STATUS_CODE" == "$EXPECTED_STATUS" ]]; then
    echo -e "${GREEN}PASS: $TEST_NAME returned $EXPECTED_STATUS as expected${NC}"
    echo "Response Header:"
    cat "$RESPONSE_HEADER"
    echo
    echo "Response Body:"
    cat "$RESPONSE_BODY"
    echo
  else
    echo -e "${RED}FAIL: $TEST_NAME expected $EXPECTED_STATUS, got $STATUS_CODE${NC}"
    local ERROR_MESSAGE=$(grep -i "^Error-Message:" "$RESPONSE_HEADER" | cut -d' ' -f2- | tr -d '\r')
    echo "  ERROR_CODE: $STATUS_CODE"
    echo "  Response header and body saved at: $TEST_DIR"
    exit 1
  fi
}
