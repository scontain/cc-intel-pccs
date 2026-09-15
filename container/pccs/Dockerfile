# SPDX-License-Identifier: BSD-3-Clause
#
# PCCS 1.27 plus the Kubernetes health-probe patch. The patch is a verbatim
# export of commit on the fork, which is proposed to upstream; it stays separate so it can
# be dropped cleanly once it ships in a DCAP release.

ARG NODE_VERSION=20.12.2

FROM docker.io/library/debian:12 AS builder

ARG NODE_VERSION
ARG PCCS_VERSION=DCAP_1.27
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

RUN git clone --depth 1 --branch "$PCCS_VERSION" "$PCCS_REPOSITORY" "$SOURCE_DIRECTORY"

COPY container/pccs/patches/0001-add-health-probe-endpoints.patch /tmp/

RUN git -C "$SOURCE_DIRECTORY" apply --check /tmp/0001-add-health-probe-endpoints.patch \
    && git -C "$SOURCE_DIRECTORY" apply /tmp/0001-add-health-probe-endpoints.patch

WORKDIR $SOURCE_DIRECTORY/service

RUN npm config set proxy "$http_proxy" \
    && npm config set https-proxy "$https_proxy" \
    && npm config set engine-strict true \
    && npm install

FROM docker.io/library/debian:12-slim

ARG NODE_VERSION
ARG USER=pccs
ARG GROUP=$USER
ARG UID=70636373
ARG GID=$UID
ARG DATA_DIRECTORY=/data

ENV NODE_ENV=production

RUN apt-get update -yq \
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
