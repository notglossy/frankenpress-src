# FrankenPress Base Images

Base FrankenPHP Docker images for [FrankenPress](https://github.com/notglossy/frankenpress), built with the latest Go and Caddy versions.

## Overview

This repository builds multi-architecture FrankenPHP base images on [Docker Hardened Images](https://docs.docker.com/dhi/) (DHI) using GitHub Actions. DHI has no thread-safe (ZTS) PHP, which FrankenPHP requires, so PHP is compiled here from the official php.net source tarball against DHI's own hardened Debian packages (`dhi.io/deb`). FrankenPHP is built with DHI's Go toolchain.

The runtime image is a clean `dhi.io/debian-base:trixie` with only PHP, FrankenPHP and the libraries they load copied in. Every added library is a DHI-built package with a dpkg `status.d` entry, so vulnerability scanners and SBOMs see it.

## Supported Variants

### PHP Versions
- 8.5
- 8.4
- 8.3
- 8.2

### Base
- Debian Trixie (Debian 13), via `dhi.io/debian-base:trixie`

### Architectures
- AMD64 (x86_64)
- ARM64 (aarch64)

### Image Types
- **Runtime** (`php<version>`): minimal image. Runs as non-root (UID 65532), no apt, no compilers.
- **Dev** (`php<version>-dev`): full build environment with headers, compilers, apt and [PIE](https://github.com/php/pie). Use it to compile extensions, then copy the result onto the runtime image.

## Image Tags

Images are hosted on GitHub Container Registry with both multi-architecture manifests and architecture-specific tags.

### Multi-Architecture Manifests (Recommended)

```
ghcr.io/notglossy/frankenpress-src:php<version>
ghcr.io/notglossy/frankenpress-src:php<version>-trixie
ghcr.io/notglossy/frankenpress-src:php<version>-dev
ghcr.io/notglossy/frankenpress-src:php<version>-trixie-dev
```

### Architecture-Specific Tags

```
ghcr.io/notglossy/frankenpress-src:php<version>-trixie-<arch>
ghcr.io/notglossy/frankenpress-src:php<version>-trixie-dev-<arch>
```

Each architecture-specific image is also tagged with the git commit SHA, e.g. `php8.4-trixie-amd64-<git-sha>`.

## Features

- ZTS PHP compiled from the latest patch release of each minor version (checksum-verified)
- FrankenPHP with Caddy, Vulcain and Brotli compression
- File watcher library (libwatcher-c)
- `opcache` and `sodium` enabled by default
- Bundled extensions built as shared modules but not enabled: `bcmath`, `exif`, `ffi`, `gd`, `intl`, `mysqli`, `pdo_mysql`, `zip`. Enable with an ini file, e.g. `echo extension=gd > $PHP_INI_DIR/conf.d/gd.ini`
- `CAP_NET_BIND_SERVICE` on the `frankenphp` binary, so it can bind ports 80/443 as non-root
- **Supply chain security**: All images include SLSA provenance attestations and SBOMs

## Adding Extensions

Install PECL extensions with PIE in the dev image, then use `fp-collect-runtime` to gather them and the DHI packages they need into a directory that is copied onto the runtime image:

```dockerfile
FROM ghcr.io/notglossy/frankenpress-src:php8.4-dev AS build
RUN apt-get update && apt-get install -y --no-install-recommends libmagickwand-dev \
    && pie install apcu/apcu phpredis/phpredis imagick/imagick \
    && fp-collect-runtime /rootfs

FROM ghcr.io/notglossy/frankenpress-src:php8.4
COPY --from=build /rootfs/ /
```

`fp-collect-runtime <dest> [package ...]` copies `/usr/local` (minus headers and build tools), resolves every shared library with `ldd`, and copies the owning packages that the runtime base doesn't already have. Extra packages, such as `ghostscript`, can be named to copy them whole.

## Build Process

Images are automatically built using GitHub Actions on:
- Pushes to the `main` branch
- A weekly schedule (Saturdays 02:00 UTC), to pick up PHP, Go and DHI package updates
- Pull requests (build and smoke test only, no push - single PHP 8.4 amd64 image)
- Manual workflow dispatch

AMD64 images build on `ubuntu-latest` and ARM64 on `ubuntu-24.04-arm` native runners, so no QEMU emulation is needed.

Pulling from `dhi.io` uses the `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` secrets.

## Local Building

Log in to DHI with your Docker Hub account first:

```bash
docker login dhi.io
```

```bash
docker build --build-arg PHP_VERSION=8.4 -t frankenpress-src:local .
docker build --build-arg PHP_VERSION=8.4 --target dev -t frankenpress-src:local-dev .
```

## Pulling Images

Images are publicly available from GitHub Container Registry.

Pull a multi-architecture image (recommended):
```bash
docker pull ghcr.io/notglossy/frankenpress-src:php8.4
```

Or pull a specific architecture:
```bash
docker pull ghcr.io/notglossy/frankenpress-src:php8.4-trixie-amd64
```

## Supply Chain Security

All images include cryptographically signed attestations for supply chain verification.

### Verifying Attestations

Verify the provenance (build origin) of an image:
```bash
docker buildx imagetools inspect ghcr.io/notglossy/frankenpress-src:php8.4-trixie-amd64 --format "{{ json .Provenance }}"
```

View the Software Bill of Materials (SBOM):
```bash
docker buildx imagetools inspect ghcr.io/notglossy/frankenpress-src:php8.4-trixie-amd64 --format "{{ json .SBOM }}"
```

### What's Included

- **SLSA Provenance**: Verifiable record of how the image was built (GitHub Actions workflow, commit SHA, build parameters)
- **SBOM**: Complete list of software packages and dependencies in the image

These attestations are automatically generated during the build process and signed by GitHub's OIDC identity provider.

## Usage in FrankenPress

These base images are consumed by the [FrankenPress](https://github.com/notglossy/frankenpress) project to create production-ready WordPress hosting environments.

## License

MIT
