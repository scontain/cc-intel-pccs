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

# Directory for full command output; CI uploads tests/tmp as an artifact, so
# anything written here stays available without cluttering the job log.
log_dir() {
  local dir="${TMP_WORKDIR:-tests/tmp}/logs"
  mkdir -p "$dir"
  echo "$dir"
}

# run_quiet NAME CMD...: runs CMD with its output captured to <log_dir>/NAME.log
# and prints one line. On failure it prints the tail of the log and returns
# CMD's status, so callers under `set -e` still stop.
run_quiet() {
  local name="$1"
  shift
  local log
  log="$(log_dir)/$name.log"

  if "$@" > "$log" 2>&1; then
    echo -e "${GREEN}ok${NC}  $name"
  else
    local rc=$?
    echo -e "${RED}FAILED${NC}  $name (exit $rc), last 40 lines of $log:"
    tail -n 40 "$log"
    return "$rc"
  fi
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

# Runs PCKIDRetrievalTool (unpacked by run-all.sh) against the deployed PCCS,
# writing its CSV to $1. The tool loads its bundled libsgx_urts from its own
# directory, and needs /dev/sgx_provision, which is root-only unless the user
# is in the sgx_prv group, so it falls back to sudo. The tool exits 0 even
# when the enclave fails to load, so an empty output file is the failure
# signal.
run_pckid_retrieval() {
  local OUTPUT_FILE="$1"
  local TOOL_DIR="$TMP_WORKDIR/PCKIDRetrievalTool"
  local RUN_AS=()

  if [ -n "$SUDO" ] && { [ ! -r /dev/sgx_provision ] || [ ! -w /dev/sgx_provision ]; }; then
    warn "No access to /dev/sgx_provision as $(id -un), running PCKIDRetrievalTool with sudo"
    RUN_AS=("$SUDO")
  fi

  local LOG
  LOG="$(log_dir)/pckid-retrieval-$(basename "$OUTPUT_FILE").log"

  "${RUN_AS[@]}" env LD_LIBRARY_PATH="$TOOL_DIR" "$TOOL_DIR/PCKIDRetrievalTool" \
    -f "$OUTPUT_FILE" \
    -url "https://$PCCS_URL" \
    -use_secure_cert false \
    -user_token "$PCCS_USER_TOKEN" > "$LOG" 2>&1 || true

  if [ ! -s "$OUTPUT_FILE" ]; then
    cat "$LOG"
    error_exit "PCKIDRetrievalTool produced no output in $OUTPUT_FILE"
  fi
  echo -e "${GREEN}ok${NC}  PCKIDRetrievalTool (log: $LOG)"
}

# Prints cluster state for the pccs namespace. Called on failure so a red run
# explains itself. The console gets only what usually points at the cause
# (pod status, warning events, recent non-debug PCCS log lines, Traefik
# errors); the full dumps go to <log_dir>/diagnostics for the CI artifact.
# Every command is best-effort because the cluster may be half-created.
dump_diagnostics() {
  local dir
  dir="$(log_dir)/diagnostics"
  mkdir -p "$dir"

  warn "---------------------------------------------"
  warn "| DIAGNOSTICS: cluster state (pccs namespace) |"
  warn "---------------------------------------------"
  kubectl get pods --all-namespaces -o wide || true

  warn ">>> warning events (pccs)"
  kubectl -n pccs get events --field-selector type=Warning --sort-by=.lastTimestamp 2>/dev/null | tail -n 20 || true

  # Describe only pods that are not fully ready; a healthy pod's describe
  # output is long and says nothing about the failure.
  kubectl -n pccs get pods --no-headers 2>/dev/null \
    | awk '{ split($2, r, "/"); if (r[1] != r[2] || $3 != "Running") print $1 }' \
    | while read -r pod; do
        warn ">>> not ready: pod/$pod"
        kubectl -n pccs describe pod "$pod" | sed -n '/^Containers:/,/^Conditions:/p;/^Events:/,$p' || true
      done

  kubectl -n pccs get pods -o name 2>/dev/null | while read -r pod; do
    kubectl -n pccs logs "$pod" --all-containers --prefix > "$dir/${pod#pod/}.log" 2>&1 || true
    kubectl -n pccs logs "$pod" --all-containers --prefix --previous > "$dir/${pod#pod/}.previous.log" 2>/dev/null || true
    # Debug lines and kubelet probe requests would crowd out the requests
    # that actually failed.
    warn ">>> logs: $pod (pccs container, last 40 lines without debug/probes; full log in $dir)"
    kubectl -n pccs logs "$pod" -c pccs --tail=2000 2>/dev/null \
      | grep -vE '\[debug\]|/healthz?/|Client Request-ID : ' | tail -n 40 || true
  done

  kubectl -n pccs get events --sort-by=.lastTimestamp > "$dir/events-pccs.txt" 2>&1 || true
  kubectl -n pccs describe pods > "$dir/describe-pods-pccs.txt" 2>&1 || true

  # Only when an ingress is in play
  if kubectl -n pccs get ingress pccs > /dev/null 2>&1; then
    kubectl -n pccs describe ingress pccs > "$dir/ingress-pccs.txt" 2>&1 || true
    kubectl -n pccs get serverstransport -o yaml > "$dir/serverstransport-pccs.yaml" 2>&1 || true
    warn ">>> ingress: pccs"
    kubectl -n pccs get ingress pccs -o wide || true
    if kubectl -n kube-system get deployment traefik > /dev/null 2>&1; then
      kubectl -n kube-system logs deployment/traefik > "$dir/traefik.log" 2>&1 || true
      warn ">>> traefik errors (last 20; full log in $dir)"
      grep -E ' (ERR|WRN) ' "$dir/traefik.log" | tail -n 20 || true
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
  # A merged or missing argument shifts every later one and silently turns
  # WORKDIR into a header; fail loudly instead.
  if [ "$#" -lt 7 ]; then
    error_exit "run_test: expected at least 7 arguments, got $#: $*"
  fi

  local TEST_NAME="$1"
  local EXPECTED_STATUS="$2"
  local BASE_URL="$3"
  local ENDPOINT="$4"
  local METHOD="$5"
  local REQUEST_BODY="$6"
  local WORKDIR="$7"
  shift 7
  local REQUEST_HEADER=("$@")

  local TEST_DIR="$WORKDIR/TEST_${TEST_NAME}"
  mkdir -p "$TEST_DIR"

  local RESPONSE_BODY="$TEST_DIR/response_body.txt"
  local RESPONSE_HEADER="$TEST_DIR/response_header.txt"

  local CURL_ARGS=(-k -sS -D "$RESPONSE_HEADER" -o "$RESPONSE_BODY" -X "$METHOD")
  
  if [[ "${#REQUEST_HEADER[@]}" -gt 0 ]]; then
    CURL_ARGS+=("${REQUEST_HEADER[@]}")
  fi

  if [[ -n "$REQUEST_BODY" ]]; then
    CURL_ARGS+=(--data-binary @"$REQUEST_BODY")
  fi

  curl "${CURL_ARGS[@]}" "https://$BASE_URL/$ENDPOINT" 2> "$TEST_DIR/curl_stderr.txt" || true

  local STATUS_CODE
  STATUS_CODE=$(head -n1 "$RESPONSE_HEADER" 2>/dev/null | awk '{print $2}')

  # Headers and body stay in TEST_DIR (part of the CI artifact); the log shows
  # them only when the test fails.
  if [[ "$STATUS_CODE" == "$EXPECTED_STATUS" ]]; then
    echo -e "${GREEN}PASS${NC}  $TEST_NAME ($STATUS_CODE)"
  else
    echo -e "${RED}FAIL${NC}  $TEST_NAME: expected $EXPECTED_STATUS, got ${STATUS_CODE:-no response}"
    echo "Request: $METHOD https://$BASE_URL/$ENDPOINT"
    if [[ -s "$RESPONSE_HEADER" ]]; then
      echo "Response header:"
      cat "$RESPONSE_HEADER"
    else
      echo "curl error:"
      cat "$TEST_DIR/curl_stderr.txt"
    fi
    if [[ -s "$RESPONSE_BODY" ]]; then
      echo "Response body (first 2000 bytes):"
      head -c 2000 "$RESPONSE_BODY" | cat -v
      echo
    fi
    exit 1
  fi
}
