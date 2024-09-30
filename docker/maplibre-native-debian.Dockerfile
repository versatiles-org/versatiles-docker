# create builder system
FROM debian:latest AS builder

RUN apt update
RUN apt install -y ccache cmake g++ git libcurl4-openssl-dev libglfw3-dev libicu-dev libjpeg-dev libpng-dev libuv1-dev libwebp-dev ninja-build pkg-config

#RUN mkdir -p /tmp
RUN git clone --depth 1 --recurse-submodules --shallow-submodules -j8 https://github.com/maplibre/maplibre-native.git /tmp

WORKDIR /tmp
RUN cmake -S . -B build -G Ninja -DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++
RUN cmake --build build -j $(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null)
RUN cd /; find . | grep "libcurl.so.4"

# create production system
FROM debian:bookworm-slim
COPY --from=builder /tmp/build/bin/* /usr/bin/
COPY --from=builder /usr/lib/x86_64-linux-gnu/* /usr/lib/x86_64-linux-gnu/
#RUN apk add --no-cache libgcc libstdc++ sqlite-libs
WORKDIR /data
#RUN cd /usr/bin/; ls -lah
ENTRYPOINT ["/usr/bin/mbgl-render"]
