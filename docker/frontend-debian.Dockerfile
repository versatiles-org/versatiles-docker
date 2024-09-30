# create builder system
FROM curlimages/curl AS builder

# download frontend
RUN curl -sL "https://github.com/versatiles-org/versatiles-frontend/releases/latest/download/frontend-rust.br.tar" > frontend.br.tar

FROM ghcr.io/versatiles-org/versatiles:latest-debian

COPY --from=builder /home/curl_user/frontend.br.tar .
