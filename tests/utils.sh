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

# Privilege helper
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi
export SUDO

# True when an SGX device node is present;
sgx_device_present() {
  [ -e /dev/sgx ] || [ -e /dev/sgx_enclave ] || [ -e /dev/sgx_provision ]
}

# Prints cluster state for the pccs namespace. Called on failure so a red run
# explains itself; every command is best-effort because the cluster may be
# half-created.
dump_diagnostics() {
  warn "---------------------------------------------"
  warn "| DIAGNOSTICS: cluster state (pccs namespace) |"
  warn "---------------------------------------------"
  kubectl get pods --all-namespaces -o wide || true
  kubectl -n pccs get events --sort-by=.lastTimestamp 2>/dev/null | tail -n 50 || true
  kubectl -n pccs describe pods -l app.kubernetes.io/name=pccs || true
  kubectl -n pccs get pods -o name 2>/dev/null | while read -r pod; do
    warn ">>> logs: $pod"
    kubectl -n pccs logs "$pod" --all-containers --prefix --tail=200 || true
  done

  # Only when an ingress is in play
  if kubectl -n pccs get ingress pccs > /dev/null 2>&1; then
    warn ">>> ingress: pccs"
    kubectl -n pccs describe ingress pccs || true
    if kubectl -n pccs get serverstransport -o name > /dev/null 2>&1; then
      kubectl -n pccs get serverstransport -o yaml || true
    fi
    if kubectl -n kube-system get deployment traefik > /dev/null 2>&1; then
      warn ">>> logs: traefik (kube-system)"
      kubectl -n kube-system logs deployment/traefik --tail=200 || true
    fi
  fi
}

# --------------------
# Test functions
# --------------------

check_required_envs () {
  local MISSING_VARS=()

  mapfile -t REQUIRED_ENVS < <(grep -E '^\s*export\s+[A-Za-z_][A-Za-z0-9_]*' ./config.env | sed -E 's/.*export\s+([A-Za-z_][A-Za-z0-9_]*)=.*/\1/')

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

  local CURL_ARGS=(-k -s -D "$RESPONSE_HEADER" -o "$RESPONSE_BODY" -X "$METHOD")
  
  if [[ "${#REQUEST_HEADER[@]}" -gt 0 ]]; then
    CURL_ARGS+=("${REQUEST_HEADER[@]}")
  fi

  if [[ -n "$REQUEST_BODY" ]]; then
    CURL_ARGS+=(--data-binary @"$REQUEST_BODY")
  fi

  curl "${CURL_ARGS[@]}" "https://$BASE_URL/$ENDPOINT" || true

  local STATUS_CODE
  STATUS_CODE=$(head -n1 "$RESPONSE_HEADER" | awk '{print $2}')

  if [[ "$STATUS_CODE" == "$EXPECTED_STATUS" ]]; then
    echo -e "\n${GREEN}PASS: $TEST_NAME returned $EXPECTED_STATUS as expected${NC}"
    
    echo "Response Header:"
    cat "$RESPONSE_HEADER"
    echo

    if [[ -s "$RESPONSE_BODY" ]]; then
      echo "Response Body:"
      cat "$RESPONSE_BODY"
      echo
    fi

  else
    echo -e "${RED}FAIL: $TEST_NAME expected $EXPECTED_STATUS, got $STATUS_CODE${NC}"
    cat "$RESPONSE_HEADER"
    exit 1
  fi
}
