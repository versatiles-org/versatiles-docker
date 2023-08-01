# create builder system
FROM ghcr.io/versatiles-org/versatiles:latest-debian

# download frontend
RUN curl -sL "https://github.com/versatiles-org/versatiles-frontend/releases/latest/download/frontend.br.tar" > frontend.br.tar
