FROM ghcr.io/versatiles-org/versatiles:latest-debian

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
RUN git clone --depth 1 -q https://github.com/systemed/tilemaker.git tilemaker
RUN cd tilemaker && make && make install

# Install Shortbread
RUN git clone --depth 1 -q --branch versatiles https://github.com/versatiles-org/shortbread-tilemaker shortbread-tilemaker
RUN cd shortbread-tilemaker && ./get-shapefiles.sh

# Add Scripts
COPY --chmod=0755 src/generate_tiles.sh .
