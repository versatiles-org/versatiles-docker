# create builder system
FROM --platform=$BUILDPLATFORM curlimages/curl as builder
ARG TARGETPLATFORM
COPY --chmod=0755 helpers/download_versatiles_binary.sh .
RUN ./download_versatiles_binary.sh "$TARGETPLATFORM-musl"

# create production system
FROM alpine:latest

# copy versatiles and selftest
WORKDIR /app
COPY --from=builder --chmod=0755 --chown=root /home/curl_user/versatiles /app/
ENV PATH="/app/:$PATH"
