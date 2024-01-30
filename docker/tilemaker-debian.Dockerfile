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
    liblua5.1-0-dev \
    libprotobuf-dev \
    libshp-dev \
    libsqlite3-dev \
    osmium-tool \
    protobuf-compiler \
    rapidjson-dev \
    unzip \
    wget

# Install Tilemaker
RUN cd ~ && git clone --depth 1 -q --branch v2.4.0 https://github.com/systemed/tilemaker.git tilemaker
RUN cd ~/tilemaker && make "CONFIG=-DFLOAT_Z_ORDER"
RUN cd ~/tilemaker && make install

# Install Shortbread
RUN cd ~ && git clone -q https://github.com/versatiles-org/shortbread-tilemaker shortbread-tilemaker
RUN cd ~/shortbread-tilemaker && ./get-shapefiles.sh
