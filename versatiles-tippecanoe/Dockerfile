# syntax=docker/dockerfile:1

###############################################################################
# ⛏️  Builder stage                                                             #
###############################################################################

ARG TIPPECANOE_VERSION=v2.34.0

FROM versatiles/versatiles:alpine AS builder
ARG TIPPECANOE_VERSION

# Build dependencies
RUN apk add --no-cache --virtual .build-deps \
    git \
    make \
    g++ \
    sqlite-dev \
    zlib-dev

WORKDIR /src

# Shallow‑clone the requested tag for reproducible builds
RUN git clone --depth 1 --branch "${TIPPECANOE_VERSION}" https://github.com/felt/tippecanoe.git .

# Compile (binaries are produced in /src)
RUN make -j"$(nproc)"

###############################################################################
# 🚀 Runtime stage                                                             #
###############################################################################

FROM versatiles/versatiles:alpine

# Copy the compiled binaries only (keeps image small)
COPY --from=builder /src/tippecanoe /src/tippecanoe-json-tool /src/tippecanoe-decode /src/tile-join /usr/local/bin/

# Minimal runtime libs
RUN apk add --no-cache libstdc++ sqlite-libs zlib

WORKDIR /data
