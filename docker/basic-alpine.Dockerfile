# create builder system
FROM --platform=$BUILDPLATFORM curlimages/curl as builder

ARG TARGETPLATFORM
ARG BUILDPLATFORM

COPY helpers/download_versatiles.sh download_versatiles.sh
RUN sh download_versatiles.sh "$TARGETPLATFORM"

# create production system
FROM --platform=$TARGETPLATFORM alpine:latest

# install dependencies
RUN apk add --no-cache sqlite

# copy versatiles, frontend and selftest
COPY --from=builder /home/curl_user/versatiles /usr/bin/
COPY helpers/versatiles_selftest.sh .
