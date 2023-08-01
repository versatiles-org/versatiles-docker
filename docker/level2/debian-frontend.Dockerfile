# create builder system
FROM debian:stable as builder

# download frontend
RUN apt update && \
    apt install -y curl && \
    curl -sL "https://github.com/versatiles-org/versatiles-frontend/releases/latest/download/frontend.br.tar" > frontend.br.tar

FROM ghcr.io/versatiles-org/versatiles:latest-debian

COPY --from=builder frontend.br.tar .
