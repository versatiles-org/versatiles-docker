# syntax=docker/dockerfile:1.7

FROM debian:13-slim AS versatiles-gdal
LABEL maintainer="Michael Kreil <versatiles@michael-kreil.de>"
LABEL org.opencontainers.image.source="https://github.com/versatiles-org/versatiles-docker"
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
RUN \
  apt-get update; \
  apt-get install -y --no-install-recommends build-essential ca-certificates clang curl git sudo; \
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y; \
  . "$HOME/.cargo/env"; \
  mkdir -p /app; \
  git clone --depth 1 https://github.com/versatiles-org/versatiles-rs.git /app/versatiles-rs; \
  cd /app/versatiles-rs || exit 1; \
  ./scripts/install-gdal.sh; \
  ./scripts/build-release.sh; \
  \
  mv /app/versatiles-rs/.toolchain/gdal /app/; \
  rm -rf /app/gdal/bin; \
  mv /app/versatiles-rs/target/release/versatiles /app/; \
  strip /app/versatiles; \
  rm -r /app/versatiles-rs; \
  \
  # 6) Remove typical *-dev packages pulled in
  # dev_pkgs="$(dpkg -l | awk '/^ii/ && $2 ~ /-dev$/ {print $2}')" || true; \
  # if [ -n "${dev_pkgs:-}" ]; then \
  #   apt-get purge -y --allow-remove-essential --auto-remove ${dev_pkgs} || true; \
  # fi; \
  apt-get purge -y --auto-remove build-essential clang cmake cpp gcc git; \
  apt-get autoremove -y; \
  apt-get clean; \
  \
  # 8) Remove development artifacts: headers, static libs, pkgconfig/cmake files
  rm -rf /usr/include/* || true; \
  find /usr/lib -type f \( -name '*.a' -o -name '*.la' \) -delete || true; \
  find /usr/lib -type d \( -name 'pkgconfig' -o -name 'cmake' \) -exec rm -rf {} + || true; \
  find /usr/lib/* -maxdepth 1 -type d \( -name 'pkgconfig' -o -name 'cmake' \) -exec rm -rf {} + || true; \
  \
  # 9) Remove docs, manpages, locales
  rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/locale/* || true; \
  \
  # 10) Drop cargo/rust caches and the source tree
  rm -rf /root/.cargo /root/.rustup /root/.cache || true; \
  \
  # 11) Drop apt metadata
  rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin || true; \
  rm -rf /tmp/* /var/tmp/* || true; \
  \
  cd /; \
  dpkg-query -Wf '${Installed-Size}\t${Package}\n' | sort -n
  
ENV LD_LIBRARY_PATH=/app/gdal/lib
WORKDIR /data
ENTRYPOINT ["/app/versatiles"]
