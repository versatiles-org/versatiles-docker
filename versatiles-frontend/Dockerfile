# syntax=docker/dockerfile:1

###############################################################################
## ─────────────────────────────  builders  ───────────────────────────────── ##
###############################################################################

FROM --platform=$BUILDPLATFORM curlimages/curl:8.11.1 AS builder
ARG TARGETPLATFORM
WORKDIR /app
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN curl -sL "https://github.com/versatiles-org/versatiles-frontend/releases/latest/download/frontend-dev.br.tar.gz" | gzip -d >frontend-dev.br.tar

###############################################################################
## ─────────────────────────────  runtimes  ──────────────────────────────── ##
###############################################################################

# ==== 1. Alpine (musl) =======================================================
FROM versatiles/versatiles:alpine AS versatiles-alpine
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"
COPY --from=builder /app/frontend-dev.br.tar /app
WORKDIR /data
ENTRYPOINT ["/app/versatiles", "server", "--static" , "/app/frontend-dev.br.tar"]

# ==== 2. Scratch (static musl) ==============================================
FROM versatiles/versatiles:scratch AS versatiles-scratch
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"
COPY --from=builder /app/frontend-dev.br.tar /app
WORKDIR /data
ENTRYPOINT ["/app/versatiles", "server", "--static" , "/app/frontend-dev.br.tar"]

# ==== 3. Debian slim (glibc) =================================================
FROM versatiles/versatiles:debian AS versatiles-debian
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"
COPY --from=builder /app/frontend-dev.br.tar /app
WORKDIR /data
ENTRYPOINT ["/app/versatiles", "server", "--static" , "/app/frontend-dev.br.tar"]
