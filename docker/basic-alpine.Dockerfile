# create builder system
FROM --platform=$BUILDPLATFORM curlimages/curl as builder
ARG TARGETPLATFORM
COPY --chmod=0755 helpers/download.sh download.sh
RUN ./download.sh "$TARGETPLATFORM-musl"

# create production system
FROM alpine:latest
RUN apk add --no-cache libgcc sqlite-dev

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
