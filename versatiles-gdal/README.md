# Docker Image: versatiles/versatiles-gdal


A minimal, lightweight, production-ready Docker image for [VersaTiles](https://github.com/versatiles-org/versatiles-rs) with [GDAL](https://gdal.org/) support.  
This enables the VPL operation [`from_gdal_raster`](https://github.com/versatiles-org/versatiles-rs/tree/main/versatiles_pipeline#from_gdal_raster), allowing VersaTiles to read raster formats such as GeoTIFF, JPEG2000, and others.

**Base image:** Debian Linux  
**Architectures:** `linux/amd64`, `linux/arm64`

## Quick Start

Pull and run the image:

```sh
docker run -it versatiles/versatiles-gdal
```

You can pass any [VersaTiles CLI arguments](https://github.com/versatiles-org/versatiles-rs?tab=readme-ov-file#usage).

For example, convert a GeoTIFF into map tiles:
```sh
echo 'from_gdal_raster filename=satellite.tif' > satellite.vpl
docker run -it --rm -v $(pwd):/data versatiles/versatiles-gdal convert satellite.vpl satellite.versatiles
```

## About

This Docker image is built from the [versatiles-org/versatiles-docker](https://github.com/versatiles-org/versatiles-docker) repository, specifically the [versatiles-gdal/](https://github.com/versatiles-org/versatiles-docker/tree/main/versatiles-gdal) subfolder.

## License

Distributed under the MIT License.