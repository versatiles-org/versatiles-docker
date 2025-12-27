# syntax=docker/dockerfile:1

###############################################################################
## ─────────────────────────────  builders  ───────────────────────────────── ##
###############################################################################

FROM --platform=$BUILDPLATFORM curlimages/curl:8.17.0 AS builder
ARG TARGETPLATFORM
WORKDIR /app
COPY ./scripts/download_versatiles_binary.sh .

# ---- musl builder ----------------------------------------------------------
FROM --platform=$BUILDPLATFORM builder AS builder-musl
RUN ./download_versatiles_binary.sh "${TARGETPLATFORM}-musl"

# ---- glibc/gnu builder ------------------------------------------------------
FROM --platform=$BUILDPLATFORM builder AS builder-gnu
RUN ./download_versatiles_binary.sh "${TARGETPLATFORM}-gnu"

###############################################################################
## ─────────────────────────────  runtimes  ──────────────────────────────── ##
###############################################################################

# ==== 1. Alpine (musl) =======================================================
FROM alpine:3.23 AS versatiles-alpine
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"
RUN apk add --no-cache tini
COPY --from=builder-musl --chmod=0755 --chown=root /app/versatiles /app/
WORKDIR /data
ENTRYPOINT ["/sbin/tini", "--", "/app/versatiles"]

# ==== 2. Scratch (static musl) ==============================================
FROM scratch AS versatiles-scratch
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"
COPY --from=builder-musl --chmod=0755 /app/versatiles /app/
WORKDIR /data
ENTRYPOINT ["/app/versatiles"]

# ==== 3. Debian slim (glibc) =================================================
FROM debian:13-slim AS versatiles-debian
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"
RUN apt-get update && apt-get install -y --no-install-recommends tini && rm -rf /var/lib/apt/lists/*
COPY --from=builder-gnu --chmod=0755 --chown=root /app/versatiles /app/
WORKDIR /data
ENTRYPOINT ["/usr/bin/tini", "--", "/app/versatiles"]
