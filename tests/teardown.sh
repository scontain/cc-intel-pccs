#!/bin/bash

set -euo pipefail

source ./tests/utils.sh

info "--------------------------------------------------------------"
info "| SETUP ENVIRONMENT: Checking required environment variables |"
info "--------------------------------------------------------------"

check_required_envs

info "---------------------------------------------"
info "| TEARDOWN ENVIRONMENT: Cleaning /etc/hosts  |"
info "---------------------------------------------"

LINE="127.0.0.1 $PCCS_URL"

if grep -qxF "$LINE" /etc/hosts; then
  sudo sed -i.bak "/[[:space:]]$PCCS_URL$/d" /etc/hosts
  echo "Removed entry for $PCCS_URL from /etc/hosts"
else
  echo "No /etc/hosts entry found for $PCCS_URL"
fi

info "---------------------------------------------"
info "| TEARDOWN ENVIRONMENT: Deleting cluster     |"
info "---------------------------------------------"

k3d cluster delete "$CLUSTER_NAME"

echo -e "${GREEN}Teardown complete!${NC}"
