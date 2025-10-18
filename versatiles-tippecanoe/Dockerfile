# syntax=docker/dockerfile:1

###############################################################################
# ⛏️  Builder stage
###############################################################################


FROM versatiles/versatiles:alpine AS builder
ARG TIPPECANOE_VERSION
ENV TIPPECANOE_VERSION=${TIPPECANOE_VERSION}

RUN apk add --no-cache --virtual .build-deps \
    bash \
    git \
    make \
    g++ \
    binutils \
    sqlite-dev \
    zlib-dev

WORKDIR /src
RUN git clone --depth 1 --branch "$TIPPECANOE_VERSION" https://github.com/felt/tippecanoe.git .

RUN make -j"$(nproc)" && \
    strip --strip-unneeded tippecanoe* tile-join # slim the binaries

###############################################################################
# 🚀 Runtime stage
###############################################################################

FROM versatiles/versatiles:alpine AS versatiles-tippecanoe

LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"

COPY --from=builder /src/tippecanoe /src/tippecanoe-json-tool /src/tippecanoe-decode /src/tile-join /usr/local/bin/

RUN apk add --no-cache libstdc++ sqlite-libs zlib

WORKDIR /data
ENV PATH="/app:${PATH}"
ENTRYPOINT ["tippecanoe"]
