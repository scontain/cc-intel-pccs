#!/bin/bash

set -euo pipefail

source ./tests/utils.sh

info "------------------------------------------------------"
info "| TLS TESTS (server certificate renewal, no restart) |"
info "------------------------------------------------------"

# cert-manager renews pccs-tls; the kubelet refreshes the mounted Secret
# volume and PCCS re-reads the pair (TlsReloadIntervalSeconds, default 60),
# so every pod must serve the new certificate without restarting. Before
# this, pods kept the certificate they started with until it expired and
# Traefik refused the backend connection.

export RENEWAL_WORKDIR="$TMP_WORKDIR/tls/cert_renewal"
mkdir -p "$RENEWAL_WORKDIR"

NAMESPACE="pccs"
RELEASE="pccs"
SERVER_NAME="$RELEASE.$NAMESPACE.svc"
LOCAL_PORT=18443
# kubelet Secret volume refresh (sync period + cache) plus one reload interval
RELOAD_TIMEOUT=240

kubectl -n "$NAMESPACE" get secret "$RELEASE-ca" -o jsonpath='{.data.ca\.crt}' | base64 -d > "$RENEWAL_WORKDIR/ca.crt"

secret_serial() {
  kubectl -n "$NAMESPACE" get secret "$RELEASE-tls" -o jsonpath='{.data.tls\.crt}' \
    | base64 -d | openssl x509 -noout -serial | cut -d= -f2
}

# Serial of the certificate POD presents on a fresh connection, verified the
# way Traefik verifies it: chained to the chart CA, SAN matching SERVER_NAME.
# Prints nothing when the pod cannot be reached or the certificate does not
# verify.
served_serial() {
  local pod="$1"
  local pf_log="$RENEWAL_WORKDIR/port-forward-${pod#pod/}.log"

  kubectl -n "$NAMESPACE" port-forward "$pod" "$LOCAL_PORT:8081" > "$pf_log" 2>&1 &
  local pf_pid=$!
  for _ in $(seq 1 20); do
    grep -q "Forwarding from" "$pf_log" && break
    sleep 0.5
  done

  openssl s_client -connect "127.0.0.1:$LOCAL_PORT" -servername "$SERVER_NAME" \
      -CAfile "$RENEWAL_WORKDIR/ca.crt" -verify_hostname "$SERVER_NAME" -verify_return_error \
      < /dev/null 2> "$RENEWAL_WORKDIR/s_client.log" \
    | openssl x509 -noout -serial 2> /dev/null | cut -d= -f2 || true

  kill "$pf_pid" 2> /dev/null || true
  wait "$pf_pid" 2> /dev/null || true
}

restart_count() {
  kubectl -n "$NAMESPACE" get "$1" -o jsonpath="{.status.containerStatuses[?(@.name==\"$RELEASE\")].restartCount}"
}

mapfile -t PODS < <(kubectl -n "$NAMESPACE" get pods -l "app.kubernetes.io/instance=$RELEASE" -o name)
[ "${#PODS[@]}" -gt 0 ] || error_exit "No PCCS pods found in namespace $NAMESPACE"

OLD_SERIAL="$(secret_serial)"
declare -A RESTARTS
for pod in "${PODS[@]}"; do
  RESTARTS[$pod]="$(restart_count "$pod")"
  [ -n "${RESTARTS[$pod]}" ] || error_exit "No restart count for container $RELEASE in $pod"
  SERVED="$(served_serial "$pod")"
  [ "$SERVED" = "$OLD_SERIAL" ] \
    || error_exit "$pod serves '${SERVED:-nothing verifiable}' before renewal, expected $OLD_SERIAL ($(tail -n 3 "$RENEWAL_WORKDIR/s_client.log"))"
done
echo -e "${GREEN}ok${NC}  ${#PODS[@]} pod(s) serve the current certificate $OLD_SERIAL"

# Same trigger as "cmctl renew": mark the Certificate as issuing. Deleting the
# Secret would also work, but would briefly remove a CA Secret that the
# Traefik ServersTransport references.
run_quiet "cert-renew-trigger" kubectl -n "$NAMESPACE" patch certificate "$RELEASE-tls" \
  --subresource=status --type=json \
  -p "[{\"op\":\"add\",\"path\":\"/status/conditions/-\",\"value\":{\"type\":\"Issuing\",\"status\":\"True\",\"reason\":\"ManuallyTriggered\",\"message\":\"Renewal triggered by tests/tls/cert_renewal.sh\",\"lastTransitionTime\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}}]"

NEW_SERIAL=""
for _ in $(seq 1 60); do
  NEW_SERIAL="$(secret_serial)"
  [ "$NEW_SERIAL" != "$OLD_SERIAL" ] && break
  sleep 2
done
[ "$NEW_SERIAL" != "$OLD_SERIAL" ] || error_exit "cert-manager did not reissue $RELEASE-tls within 120s"
echo -e "${GREEN}ok${NC}  cert-manager reissued $RELEASE-tls: $OLD_SERIAL -> $NEW_SERIAL"

for pod in "${PODS[@]}"; do
  SERVED=""
  DEADLINE=$((SECONDS + RELOAD_TIMEOUT))
  while [ "$SECONDS" -lt "$DEADLINE" ]; do
    SERVED="$(served_serial "$pod")"
    [ "$SERVED" = "$NEW_SERIAL" ] && break
    sleep 10
  done
  [ "$SERVED" = "$NEW_SERIAL" ] \
    || error_exit "$pod still serves '${SERVED:-nothing verifiable}' ${RELOAD_TIMEOUT}s after renewal, expected $NEW_SERIAL"
  [ "$(restart_count "$pod")" = "${RESTARTS[$pod]}" ] \
    || error_exit "$pod restarted to pick up the certificate; it should have reloaded it in place"
  echo -e "${GREEN}ok${NC}  $pod serves the renewed certificate without a restart"
done

run_test "INGRESS_AFTER_RENEWAL" "200" "$PCCS_URL" "healthz/ready" "GET" "" "$RENEWAL_WORKDIR"

echo -e "${GREEN}Certificate renewal tests completed successfully!${NC}"
