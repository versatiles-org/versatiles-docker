# syntax=docker/dockerfile:1

FROM versatiles/versatiles:debian AS versatiles-tilemaker

RUN apt update -y && \
    DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
        aria2 \
        build-essential \
        curl \
        ca-certificates \
        gdal-bin \
        git \
        libboost-dev \
        libboost-filesystem-dev \
        libboost-iostreams-dev \
        libboost-program-options-dev \
        libboost-system-dev \
        liblua5.3-dev lua5.3 \
        libshp-dev \
        libsqlite3-dev \
        osmium-tool \
        rapidjson-dev \
        unzip \
        wget \
        zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/systemed/tilemaker.git /tmp/tilemaker && \
    make -C /tmp/tilemaker && \
    make -C /tmp/tilemaker install && \
    rm -rf /tmp/tilemaker

# Add Shortbread configuration
RUN git clone --depth 1 -q --branch versatiles https://github.com/versatiles-org/shortbread-tilemaker /opt/shortbread && \
    bash /opt/shortbread/get-shapefiles.sh && \
    rm /opt/shortbread/data/*.zip && \
    rm -rf /opt/shortbread/.git /opt/shortbread/data/simplified-water-polygons-split-3857

WORKDIR /opt/shortbread
COPY --chmod=0755 scripts/generate_tiles.sh /usr/local/bin/generate_tiles

ENTRYPOINT ["generate_tiles"]