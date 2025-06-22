# syntax=docker/dockerfile:1

FROM versatiles/versatiles-debian

RUN apt update -y && apt install -y \
    aria2 \
    build-essential \
    curl \
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
    zlib1g-dev

# Install Tilemaker
RUN \
    git clone --depth 1 -q https://github.com/systemed/tilemaker.git tilemaker && \
    cd tilemaker && \
    make && \
    make install && \
    cd .. && \
    rm -r tilemaker

# Add Shortbread configuration
RUN \
    git clone --depth 1 -q --branch versatiles https://github.com/versatiles-org/shortbread-tilemaker shortbread-tilemaker && \
    cd shortbread-tilemaker && \
    bash get-shapefiles.sh && \
    rm data/*.zip && \
    rm -r .git data/simplified-water-polygons-split-3857

# Add Scripts
COPY --chmod=0755 ./scripts/generate_tiles.sh .

ENTRYPOINT [ "bash", "generate_tiles.sh" ]