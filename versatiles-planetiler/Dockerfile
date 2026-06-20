# syntax=docker/dockerfile:1

###############################################################################
# Planetiler JAR Builder
#
# The planetiler distribution JAR is architecture-independent, so it is built
# once on the native build platform ($BUILDPLATFORM) and reused for every
# target architecture.
###############################################################################

FROM --platform=$BUILDPLATFORM eclipse-temurin:21-jdk AS builder-planetiler
WORKDIR /src
RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        git \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Build the VersaTiles fork of Planetiler with the Shortbread profile.
RUN git clone --depth 1 --recurse-submodules \
        --branch feature/shortbread-java-profile \
        https://github.com/versatiles-org/planetiler.git /src && \
    ./mvnw -q -pl planetiler-dist -am package -DskipTests && \
    cp planetiler-dist/target/*with-deps*.jar /planetiler.jar

###############################################################################
# VersaTiles Binary Builder
###############################################################################

FROM --platform=$BUILDPLATFORM curlimages/curl:8.20.0 AS builder-versatiles
ARG TARGETPLATFORM
WORKDIR /app
COPY ./scripts/download_versatiles_binary.sh .
RUN ./download_versatiles_binary.sh "${TARGETPLATFORM}-gnu"

###############################################################################
# Main Build
###############################################################################

FROM eclipse-temurin:21-jre AS versatiles-planetiler
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        aria2 \
        ca-certificates \
        curl \
        jq \
        tini && \
    rm -rf /var/lib/apt/lists/*

# Add Planetiler (from builder)
COPY --from=builder-planetiler /planetiler.jar /opt/planetiler/planetiler.jar

# Add VersaTiles (from builder)
COPY --from=builder-versatiles --chmod=0755 /app/versatiles /usr/local/bin/versatiles

WORKDIR /app
STOPSIGNAL SIGTERM

COPY --chmod=0755 ./versatiles-planetiler/scripts/generate_tiles.sh /usr/local/bin/generate_tiles

ENTRYPOINT ["tini", "-g", "--", "generate_tiles"]
