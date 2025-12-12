# syntax=docker/dockerfile:1

###############################################################################
## ─────────────────────────────  builders  ───────────────────────────────── ##
###############################################################################

FROM --platform=$BUILDPLATFORM curlimages/curl:8.17.0 AS builder-frontend
ARG TARGETPLATFORM
WORKDIR /app
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN curl -sL "https://github.com/versatiles-org/versatiles-frontend/releases/latest/download/frontend-dev.br.tar.gz" | gzip -d >frontend-dev.br.tar

FROM --platform=$BUILDPLATFORM curlimages/curl:8.17.0 AS builder-versatiles
ARG TARGETPLATFORM
WORKDIR /app
COPY ./scripts/download_versatiles_binary.sh .

# ---- musl builder (for Alpine/Scratch) -------------------------------------
FROM --platform=$BUILDPLATFORM builder-versatiles AS builder-versatiles-musl
RUN ./download_versatiles_binary.sh "${TARGETPLATFORM}-musl"

# ---- glibc/gnu builder (for Debian) ----------------------------------------
FROM --platform=$BUILDPLATFORM builder-versatiles AS builder-versatiles-gnu
RUN ./download_versatiles_binary.sh "${TARGETPLATFORM}-gnu"

###############################################################################
## ─────────────────────────────  runtimes  ──────────────────────────────── ##
###############################################################################

# ==== 1. Alpine (musl) =======================================================
FROM alpine:3.23 AS versatiles-alpine
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"
WORKDIR /app
COPY --from=builder-versatiles-musl --chmod=0755 --chown=root /app/versatiles .
COPY --from=builder-frontend /app/frontend-dev.br.tar .
WORKDIR /data
ENTRYPOINT ["/app/versatiles", "server", "--static" , "/app/frontend-dev.br.tar"]

# ==== 2. Scratch (static musl) ==============================================
FROM scratch AS versatiles-scratch
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"
WORKDIR /app
COPY --from=builder-versatiles-musl --chmod=0755 /app/versatiles .
COPY --from=builder-frontend /app/frontend-dev.br.tar .
WORKDIR /data
ENTRYPOINT ["/app/versatiles", "server", "--static" , "/app/frontend-dev.br.tar"]

# ==== 3. Debian slim (glibc) =================================================
FROM debian:13-slim AS versatiles-debian
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"
WORKDIR /app
COPY --from=builder-versatiles-gnu --chmod=0755 --chown=root /app/versatiles .
COPY --from=builder-frontend /app/frontend-dev.br.tar .
WORKDIR /data
ENTRYPOINT ["/app/versatiles", "server", "--static" , "/app/frontend-dev.br.tar"]
