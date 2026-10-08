# SPDX-License-Identifier: BSD-3-Clause
#
# PCCS 1.27 plus the patches in container/pccs/patches, applied in file-name
# order: 0001 adds the Kubernetes health-probe endpoints, 0002 reloads the
# HTTPS key and certificate when they are renewed on disk. Each patch
# records its purpose separately so it can be dropped when upstream
# provides the fix. Later patches enforce MySQL TLS and update dependencies.

# PCCS 1.27 declares engines.node ">= 22.13.0" in service/package.json, and
# the build sets engine-strict, so an older Node fails npm install outright.
ARG NODE_VERSION=22.23.2

FROM docker.io/library/debian:12 AS builder

ARG NODE_VERSION
ARG PCCS_VERSION=DCAP_1.27
ARG PCCS_COMMIT=f945567ff842c1189a81b4fe79a57769fe39ccb9
ARG PCCS_REPOSITORY=https://github.com/intel/confidential-computing.tee.dcap.pccs.git
ARG SOURCE_DIRECTORY=/pccs

RUN DEBIAN_FRONTEND=noninteractive \
    apt-get update -yq \
    && apt-get upgrade -yq \
    && apt-get install -yq --no-install-recommends \
        ca-certificates \
        curl \
        git \
        zip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

ENV NVM_DIR=/root/.nvm
ENV NODE_ENV=production
ENV PATH=$NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH

RUN . "$NVM_DIR/nvm.sh" && nvm install "$NODE_VERSION" && nvm use "$NODE_VERSION"

RUN git clone --depth 1 --branch "$PCCS_VERSION" "$PCCS_REPOSITORY" "$SOURCE_DIRECTORY" \
    && test "$(git -C "$SOURCE_DIRECTORY" rev-parse HEAD)" = "$PCCS_COMMIT"

COPY container/pccs/patches/*.patch /tmp/patches/

RUN for patch in /tmp/patches/*.patch; do \
        git -C "$SOURCE_DIRECTORY" apply --check "$patch" \
        && git -C "$SOURCE_DIRECTORY" apply "$patch" \
        || exit 1; \
    done

WORKDIR $SOURCE_DIRECTORY/service

RUN npm config set proxy "$http_proxy" \
    && npm config set https-proxy "$https_proxy" \
    && npm config set engine-strict true \
    && npm ci --omit=dev

FROM docker.io/library/debian:12-slim

ARG NODE_VERSION
ARG USER=pccs
ARG GROUP=$USER
ARG UID=70636373
ARG GID=$UID
ARG DATA_DIRECTORY=/data

ENV NODE_ENV=production

RUN apt-get update -yq \
    && apt-get upgrade -yq \
    && apt-get install -yq --no-install-recommends ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid "$GID" "$GROUP" \
    && useradd --no-create-home --uid "$UID" --gid "$GID" --system "$USER" --shell /bin/false \
    && mkdir -p "$DATA_DIRECTORY" \
    && chown "$USER:$GROUP" "$DATA_DIRECTORY"

VOLUME ["/data"]

COPY --from=builder /root/.nvm/versions/node/v$NODE_VERSION/bin/node /usr/bin/node
COPY --from=builder --chown=$USER:$GROUP /pccs/service/ /opt/intel/pccs/

WORKDIR /opt/intel/pccs/
USER $USER

ENTRYPOINT ["/usr/bin/node", "pccs_server.js"]
