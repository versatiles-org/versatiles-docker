# syntax=docker/dockerfile:1

###############################################################################
# ⚙️  Versatiles Binary Builder
###############################################################################

FROM --platform=$BUILDPLATFORM curlimages/curl:8.17.0 AS builder-versatiles
ARG TARGETPLATFORM
WORKDIR /app
COPY ./scripts/download_versatiles_binary.sh .
RUN ./download_versatiles_binary.sh "${TARGETPLATFORM}-musl"

###############################################################################
# ⛏️  Tippecanoe Builder
###############################################################################

FROM alpine:3.23 AS builder-tippecanoe
ARG TIPPECANOE_VERSION
ENV TIPPECANOE_VERSION=${TIPPECANOE_VERSION}

RUN apk add --no-cache --virtual .build-deps \
    bash \
    git \
    make \
    g++ \
    binutils \
    sqlite-dev \
    zlib-dev

WORKDIR /src
RUN git clone --depth 1 --branch "$TIPPECANOE_VERSION" https://github.com/felt/tippecanoe.git .

RUN make -j"$(nproc)" && \
    strip --strip-unneeded tippecanoe* tile-join # slim the binaries

###############################################################################
# 🚀 Runtime
###############################################################################

FROM alpine:3.23 AS versatiles-tippecanoe

LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"

# Copy versatiles binary from dedicated builder
COPY --from=builder-versatiles --chmod=0755 --chown=root /app/versatiles /app/versatiles

# Copy tippecanoe binaries
COPY --from=builder-tippecanoe /src/tippecanoe /src/tippecanoe-json-tool /src/tippecanoe-decode /src/tile-join /usr/local/bin/

RUN apk add --no-cache libstdc++ sqlite-libs zlib tini

WORKDIR /data
ENV PATH="/app:${PATH}"
ENTRYPOINT ["/sbin/tini", "--", "tippecanoe"]
