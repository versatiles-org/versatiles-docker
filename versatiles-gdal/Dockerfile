# syntax=docker/dockerfile:1.7

###############################################################################
# ⚙️  Builder: versatiles with GDAL, and the packages it needs at runtime
###############################################################################

# Compilers, Rust and GDAL's -dev packages stay in this stage. Purging them
# from a single stage left about 90 -dev packages behind, which made up a
# third of the image's security findings and most of its size.
FROM debian:13-slim AS builder
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
# The release to build, like the other images. It also keys the build cache,
# so a new release is never served from an older build.
ARG VERSATILES_VERSION
RUN \
  apt-get update; \
  apt-get install -y --no-install-recommends build-essential ca-certificates clang curl git sudo; \
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y; \
  . "$HOME/.cargo/env"; \
  git clone --depth 1 --branch "${VERSATILES_VERSION:?}" https://github.com/versatiles-org/versatiles-rs.git /src; \
  cd /src; \
  ./scripts/install-gdal.sh; \
  # Only the CLI: the workspace also holds the Node bindings, whose LTO build
  # doubled the time and memory, enough to be killed in an 8 GB Docker VM.
  cargo build --release --locked -p versatiles -F gdal; \
  mkdir -p /out; \
  mv target/release/versatiles /out/versatiles; \
  strip /out/versatiles; \
  \
  # The Debian packages owning the shared libraries the binary links against.
  # Since Debian's /usr merge, dpkg may know a library only by its other path.
  ldd /out/versatiles | awk '/=> \// {print $3}' | while read -r lib; do \
    dpkg -S "$lib" 2>/dev/null || dpkg -S "$(realpath "$lib")"; \
  done | grep -v '^diversion by' | cut -d: -f1 | sort -u > /out/runtime-packages; \
  grep -qx 'libgdal[0-9]*' /out/runtime-packages; \
  cat /out/runtime-packages

###############################################################################
# 🚀 Runtime
###############################################################################

FROM debian:13-slim AS versatiles-gdal
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

COPY --from=builder /out/runtime-packages /tmp/runtime-packages
RUN \
  apt-get update; \
  xargs -a /tmp/runtime-packages apt-get install -y --no-install-recommends ca-certificates tini; \
  apt-get clean; \
  rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin /tmp/*; \
  rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/locale/*; \
  dpkg-query -Wf '${Installed-Size}\t${Package}\n' | sort -n

COPY --from=builder --chmod=0755 /out/versatiles /app/versatiles

# Security updates in their own step: BUILD_DATE changes daily, so this step
# isn't reused from the cache, while the slow build above still can be.
# See BUILD_DATE in scripts/utils.sh.
ARG BUILD_DATE
RUN \
  apt-get update; \
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y; \
  apt-get clean; \
  rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin; \
  rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/locale/*

WORKDIR /data
ENV PATH="$PATH:/app"
ENTRYPOINT ["/usr/bin/tini", "--", "/app/versatiles"]
