# syntax=docker/dockerfile:1

# ---------- build stage ----------
FROM --platform=$BUILDPLATFORM curlimages/curl:8.17.0 AS builder
ARG TARGETPLATFORM
WORKDIR /app
COPY ./scripts/download_versatiles_binary.sh .
RUN ./download_versatiles_binary.sh "${TARGETPLATFORM}-musl"

# ---------- runtime stage ----------
FROM alpine:3.23 AS versatiles-nginx
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"

ENV UID=10001 GID=10001 \
    BBOX="" \
    HTTP_ONLY="" \
    DOMAIN="" \
    EMAIL="" \
    FRONTEND="" \
    TILE_SOURCES="" \
    CACHE_SIZE_KEYS="" \
    CACHE_SIZE_MAX="" \
    PATH="/scripts:$PATH"

# core packages
RUN apk add --no-cache bash certbot certbot-nginx curl gzip nginx openssl su-exec tini tzdata && \
    mkdir -p /var/cache/nginx /etc/nginx/templates /data && \
    addgroup -g "$GID" vs && adduser -D -s /sbin/nologin -G vs -u "$UID" vs

# copy VersaTiles binary from builder
COPY --from=builder /app/versatiles /usr/local/bin/versatiles

# copy entrypoint
COPY ./versatiles-nginx/scripts/*.sh /scripts/
RUN chmod +x /scripts/*.sh

VOLUME ["/data"]
EXPOSE 80 443

HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD curl -f http://127.0.0.1:8090/_nginx_status || exit 1

ENTRYPOINT ["/sbin/tini","--","entrypoint.sh"]
