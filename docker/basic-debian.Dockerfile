# create builder system
FROM --platform=$BUILDPLATFORM curlimages/curl as builder
ARG TARGETPLATFORM
COPY --chmod=0755 helpers/download.sh download.sh
RUN ./download.sh "$TARGETPLATFORM-gnu"

# create production system
FROM debian:stable-slim

# install dependencies
RUN apt-get -y update && \
    apt-get -y install --no-install-recommends libsqlite3-0 && \
    apt-get -y clean && \
    apt-get -y autoremove -y && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /var/cache/*

# copy versatiles and selftest
WORKDIR /app
COPY --from=builder --chmod=0755 --chown=root /home/curl_user/versatiles /usr/local/bin/
ENV PATH="/usr/local/bin:$PATH"
COPY --chmod=0755 helpers/selftest.sh .

# test
RUN ./selftest.sh

# finalize
EXPOSE 8080
ENTRYPOINT versatiles
