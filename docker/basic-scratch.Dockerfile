# create builder system
FROM --platform=$BUILDPLATFORM curlimages/curl as builder
ARG TARGETPLATFORM
COPY --chmod=0755 helpers/download.sh .
RUN ./download.sh "$TARGETPLATFORM-musl"

# create production system
FROM scratch

# copy versatiles and selftest
WORKDIR /app
COPY --from=builder --chmod=0755 --chown=root /home/curl_user/versatiles /app/

# finalize
EXPOSE 8080
ENTRYPOINT [ "/app/versatiles" ]
