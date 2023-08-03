# Compile Versatiles Binary inside Builder
FROM rust:alpine as builder

COPY ../ /usr/src/versatiles
WORKDIR /usr/src/versatiles

RUN apk add curl gzip musl-dev openssl-dev pkgconfig sqlite-dev
RUN rustup default stable
RUN cargo install versatiles

# Create user
ENV USER=versatiles
ENV UID=1000
RUN adduser \ 
    --disabled-password \ 
    --gecos "" \ 
    --home "/nonexistent" \ 
    --shell "/sbin/nologin" \ 
    --no-create-home \ 
    --uid "${UID}" \ 
    "${USER}"

# Setup Final Docker Image
FROM scratch
WORKDIR /data/

# Copy files from builder
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group
COPY --from=builder --chown=versatiles:versatiles /usr/local/cargo/bin/versatiles /usr/bin/
COPY helpers/versatiles_selftest.sh .

USER versatiles
