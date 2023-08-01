# create builder system
FROM alpine as builder

# install dependencies
RUN apk add gcc musl-dev openssl-dev pkgconfig sqlite-dev

# install rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain stable

# install versatiles
RUN $HOME/.cargo/bin/cargo install versatiles

# create production system
FROM alpine

# install dependencies
RUN apk add --no-cache curl sqlite

# copy versatiles, frontend and selftest
COPY --from=builder /root/.cargo/bin/versatiles /usr/bin/
COPY helpers/versatiles_selftest.sh .
