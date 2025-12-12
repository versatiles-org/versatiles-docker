# syntax=docker/dockerfile:1

###############################################################################
# Versatiles Binary Builder
###############################################################################

FROM --platform=$BUILDPLATFORM curlimages/curl:8.17.0 AS builder-versatiles
ARG TARGETPLATFORM
WORKDIR /app
COPY ./scripts/download_versatiles_binary.sh .
RUN ./download_versatiles_binary.sh "${TARGETPLATFORM}-gnu"

###############################################################################
# Main Build
###############################################################################

FROM debian:13-slim AS versatiles-tilemaker
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        aria2 \
        build-essential \
        curl \
        ca-certificates \
        gdal-bin \
        git \
        libboost-dev \
        libboost-filesystem-dev \
        libboost-iostreams-dev \
        libboost-program-options-dev \
        libboost-system-dev \
        liblua5.3-dev lua5.3 \
        libshp-dev \
        libsqlite3-dev \
        osmium-tool \
        rapidjson-dev \
        unzip \
        wget \
        zlib1g-dev \
        tini && \
    rm -rf /var/lib/apt/lists/*

# Add Tilemaker
RUN git clone --depth 1 https://github.com/systemed/tilemaker.git /tmp/tilemaker && \
    make -C /tmp/tilemaker && \
    make -C /tmp/tilemaker install && \
    rm -rf /tmp/tilemaker

# Add Shortbread configuration
RUN git clone --depth 1 -q --branch versatiles https://github.com/versatiles-org/shortbread-tilemaker /opt/shortbread && \
    bash /opt/shortbread/get-shapefiles.sh && \
    rm /opt/shortbread/data/*.zip && \
    rm -rf /opt/shortbread/.git /opt/shortbread/data/simplified-water-polygons-split-3857

# Add VersaTiles (from builder instead of remote script)
COPY --from=builder-versatiles --chmod=0755 /app/versatiles /usr/local/bin/versatiles

WORKDIR /opt/shortbread
STOPSIGNAL SIGTERM

COPY --chmod=0755 ./versatiles-tilemaker/scripts/generate_tiles.sh /usr/local/bin/generate_tiles

ENTRYPOINT ["tini", "-g", "--", "generate_tiles"]