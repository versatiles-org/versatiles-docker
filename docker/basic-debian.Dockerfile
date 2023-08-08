# create builder system
FROM --platform=$BUILDPLATFORM curlimages/curl as builder
ARG TARGETPLATFORM
COPY --chmod=0755 helpers/download.sh .
RUN ./download.sh "$TARGETPLATFORM-gnu"

# create production system
FROM debian:stable-slim

# copy versatiles and selftest
WORKDIR /app
COPY --from=builder --chmod=0755 --chown=root /home/curl_user/versatiles /usr/local/bin/
ENV PATH="/usr/local/bin:$PATH"

# finalize
EXPOSE 8080
ENTRYPOINT [ "versatiles" ]
