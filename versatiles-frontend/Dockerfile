# syntax=docker/dockerfile:1

###############################################################################
## ─────────────────────────────  builders  ───────────────────────────────── ##
###############################################################################

FROM --platform=$BUILDPLATFORM curlimages/curl AS builder
ARG TARGETPLATFORM
WORKDIR /app
RUN curl -sL "https://github.com/versatiles-org/versatiles-frontend/releases/latest/download/frontend-dev.br.tar.gz" | gzip -d >frontend-dev.br.tar

###############################################################################
## ─────────────────────────────  runtimes  ──────────────────────────────── ##
###############################################################################

# ==== 1. Alpine (musl) =======================================================
FROM versatiles/versatiles:alpine AS versatiles-alpine
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"
WORKDIR /app
COPY --from=builder /app/frontend-dev.br.tar .
ENV PATH="/app:$PATH"
ENTRYPOINT ["versatiles", "server", "--static" , "frontend-dev.br.tar"]

# ==== 2. Scratch (static musl) ==============================================
FROM versatiles/versatiles:scratch AS versatiles-scratch
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"
WORKDIR /app
COPY --from=builder /app/frontend-dev.br.tar .
ENV PATH="/app"
ENTRYPOINT ["versatiles", "server", "--static" , "frontend-dev.br.tar"]

# ==== 3. Debian slim (glibc) =================================================
FROM versatiles/versatiles:debian AS versatiles-debian
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"
WORKDIR /app
COPY --from=builder /app/frontend-dev.br.tar .
ENV PATH="/app:$PATH"
ENTRYPOINT ["versatiles", "server", "--static" , "frontend-dev.br.tar"]
