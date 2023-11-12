# create builder system
FROM alpine:latest as builder

RUN apk update
RUN apk add git make sqlite-dev zlib-dev bash g++
RUN mkdir -p /tmp
RUN git clone --depth 1 https://github.com/mapbox/tippecanoe.git /tmp
ENV PREFIX=/tmp
RUN cd /tmp && make -j && make install

# create production system
FROM alpine:latest
COPY --from=builder /tmp/bin/* /usr/bin/
RUN apk add --no-cache libgcc libstdc++ sqlite-libs
WORKDIR /data
ENTRYPOINT ["tippecanoe"]
