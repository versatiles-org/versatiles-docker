# syntax=docker/dockerfile:1

###############################################################################
## ─────────────────────────────  builders  ───────────────────────────────── ##
###############################################################################

FROM --platform=$BUILDPLATFORM curlimages/curl AS builder
ARG TARGETPLATFORM
WORKDIR /app
COPY download_versatiles_binary.sh .

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
FROM alpine:latest AS versatiles-alpine
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
WORKDIR /app
COPY --from=builder-musl --chmod=0755 --chown=root /app/versatiles .
ENV PATH="/app:$PATH"
ENTRYPOINT ["versatiles"]

# ==== 2. Scratch (static musl) ==============================================
FROM scratch AS versatiles-scratch
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
WORKDIR /app
COPY --from=builder-musl --chmod=0755 /app/versatiles .
ENV PATH="/app"
ENTRYPOINT ["versatiles"]

# ==== 3. Debian slim (glibc) =================================================
FROM debian:stable-slim AS versatiles-debian
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
WORKDIR /app
COPY --from=builder-gnu --chmod=0755 --chown=root /app/versatiles .
ENV PATH="/app:$PATH"
ENTRYPOINT ["versatiles"]
