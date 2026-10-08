#!/usr/bin/env bash

# Verifies that every place carrying the PCCS version agrees. The chart's
# appVersion is the source of truth; the image tag uses its major.minor.
#
#   charts/pccs/Chart.yaml     appVersion: "1.27.0"      -> 1.27
#   charts/pccs/values.yaml    image.tag: "v1.27.0-security.1"        -> 1.27
#   container/pccs/Dockerfile  ARG PCCS_VERSION=DCAP_1.27 -> 1.27
#   config.env                 PCCS_IMAGE_TAG="v1.27.0-security.1"    -> 1.27
#
# Prints the resolved values and exits non-zero on any mismatch.

set -euo pipefail

source ./tests/utils.sh

APP_VERSION=$(sed -nE 's/^appVersion: *"?([0-9]+\.[0-9]+\.[0-9]+)"?.*/\1/p' charts/pccs/Chart.yaml)
[ -n "$APP_VERSION" ] || error_exit "Could not read appVersion from charts/pccs/Chart.yaml"
EXPECTED="${APP_VERSION%.*}"

VALUES_TAG=$(sed -nE 's/^  tag: *"v([0-9]+\.[0-9]+)[^"]*".*/\1/p' charts/pccs/values.yaml)
DOCKERFILE_TAG=$(sed -nE 's/^ARG PCCS_VERSION=DCAP_([0-9]+\.[0-9]+).*/\1/p' container/pccs/Dockerfile)
CONFIG_TAG=$(sed -nE 's/^export PCCS_IMAGE_TAG="v([0-9]+\.[0-9]+)[^"]*".*/\1/p' config.env)

info "PCCS version consistency (expected $EXPECTED from appVersion $APP_VERSION)"
printf '  %-28s %s\n' "charts/pccs/values.yaml" "${VALUES_TAG:-<not found>}" \
                     "container/pccs/Dockerfile" "${DOCKERFILE_TAG:-<not found>}" \
                     "config.env" "${CONFIG_TAG:-<not found>}"

MISMATCH=()
[ "$VALUES_TAG" = "$EXPECTED" ] || MISMATCH+=("charts/pccs/values.yaml")
[ "$DOCKERFILE_TAG" = "$EXPECTED" ] || MISMATCH+=("container/pccs/Dockerfile")
[ "$CONFIG_TAG" = "$EXPECTED" ] || MISMATCH+=("config.env")

if [ "${#MISMATCH[@]}" -gt 0 ]; then
  error_exit "PCCS version mismatch in: ${MISMATCH[*]} (expected $EXPECTED)"
fi

echo -e "${GREEN}All PCCS version references agree on $EXPECTED${NC}"

# The chart and local tests must select the same hardened image revision.
CHART_REVISION=$(sed -nE 's/^  tag: *"([^"]+)".*/\1/p' charts/pccs/values.yaml)
TEST_REVISION=$(sed -nE 's/^export PCCS_IMAGE_TAG="([^"]+)".*/\1/p' config.env)
[ "$CHART_REVISION" = "$TEST_REVISION" ] || error_exit "PCCS image revision mismatch: chart=$CHART_REVISION tests=$TEST_REVISION"
