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

# copy versatiles and selftest
WORKDIR /app
COPY --from=builder --chmod=0755 --chown=root /home/curl_user/versatiles /usr/local/bin/
RUN ls -lah /usr/local/bin/
RUN wc /usr/local/bin/versatiles
RUN /usr/local/bin/versatiles --help
COPY --chmod=0777 helpers/versatiles_selftest.sh .

RUN ls -lah
RUN sh versatiles_selftest.sh

EXPOSE 8080
ENTRYPOINT versatiles
CMD ["versatiles", "start"]