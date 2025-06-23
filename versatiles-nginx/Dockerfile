# ---------- build stage ----------
FROM alpine:latest AS builder

# runtime deps for versatiles build script
RUN apk add --no-cache curl ca-certificates

# download the static VersaTiles binary
RUN curl -Ls https://github.com/versatiles-org/versatiles-rs/raw/main/scripts/install-unix.sh | sh

# ---------- runtime stage ----------
FROM alpine:latest AS versatiles-nginx
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"

ENV UID=10001 GID=10001 \
    DOMAIN="" \
    EMAIL="" \
    FRONTEND="" \
    TILE_SOURCES="" \
    CACHE_SIZE_KEYS="" \
    CACHE_SIZE_MAX="" \
    PATH="/scripts:$PATH"

# core packages
RUN apk add --no-cache nginx certbot certbot-nginx curl bash su-exec tzdata tini gzip && \
    mkdir -p /var/cache/nginx /etc/nginx/templates /data && \
    addgroup -g "$GID" vs && adduser -D -s /sbin/nologin -G vs -u "$UID" vs

# copy VersaTiles binary from builder
COPY --from=builder /usr/local/bin/versatiles /usr/local/bin/versatiles

# copy entrypoint
COPY scripts/*.sh /scripts/
RUN chmod +x /scripts/*.sh

VOLUME ["/data"]
EXPOSE 80 443

HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD curl -f http://127.0.0.1:8090/_nginx_status || exit 1

ENTRYPOINT ["/sbin/tini","--","entrypoint.sh"]
