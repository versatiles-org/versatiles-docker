# create builder system
FROM curlimages/curl AS builder

# download frontend
RUN curl -sL "https://github.com/versatiles-org/versatiles-frontend/releases/latest/download/frontend-dev.br.tar.gz" | gzip -d > frontend-dev.br.tar

FROM ghcr.io/versatiles-org/versatiles:latest-alpine

COPY --from=builder /home/curl_user/frontend-dev.br.tar .
