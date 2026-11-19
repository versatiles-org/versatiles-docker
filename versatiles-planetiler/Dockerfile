# syntax=docker/dockerfile:1

###############################################################################
# Planetiler JAR Builder
#
# The planetiler distribution JAR is architecture-independent, so it is built
# once on the native build platform ($BUILDPLATFORM) and reused for every
# target architecture.
###############################################################################

FROM --platform=$BUILDPLATFORM eclipse-temurin:27-jdk AS builder-planetiler
WORKDIR /src
RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        git \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Build the VersaTiles fork of Planetiler. The Shortbread profile lives in its
# own repo (versatiles-org/planetiler-shortbread) and is pulled in as a git
# submodule, hence --recurse-submodules.
#
# The Maven build downloads Maven itself and every dependency, so a brief
# outage of a Maven repository fails the whole image build. It is therefore
# tried three times, 60 s and 120 s apart. Downloads that succeeded stay in
# ~/.m2 for the next attempt. -U makes Maven retry downloads that failed,
# which it otherwise remembers as missing and doesn't request again.
RUN git clone --depth 1 --recurse-submodules \
        --branch main \
        https://github.com/versatiles-org/planetiler.git /src && \
    for attempt in 1 2 3; do \
        ./mvnw -q -U -pl planetiler-dist -am package -DskipTests && break; \
        if [ "$attempt" -eq 3 ]; then exit 1; fi; \
        echo "Maven build failed (attempt $attempt of 3), retrying in $((attempt * 60)) s" >&2; \
        sleep $((attempt * 60)); \
    done && \
    cp planetiler-dist/target/*with-deps*.jar /planetiler.jar

###############################################################################
# VersaTiles Binary Builder
###############################################################################

FROM --platform=$BUILDPLATFORM curlimages/curl:8.23.0 AS builder-versatiles
ARG TARGETPLATFORM
WORKDIR /app
COPY ./scripts/download_versatiles_binary.sh .
ARG VERSATILES_VERSION
RUN ./download_versatiles_binary.sh "${TARGETPLATFORM}-gnu" "${VERSATILES_VERSION}"

###############################################################################
# Main Build
###############################################################################

FROM eclipse-temurin:27-jre AS versatiles-planetiler
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        aria2 \
        ca-certificates \
        curl \
        osmium-tool \
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
