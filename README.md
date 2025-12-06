# FrankenPress Base Images

Base FrankenPHP Docker images for [FrankenPress](https://github.com/notglossy/frankenpress), built with the latest Go and Caddy versions.

## Overview

This repository builds multi-architecture FrankenPHP base images using GitHub Actions. These images are designed to be used as the foundation for the FrankenPress project, providing optimized FrankenPHP builds with various PHP versions across different Debian distributions and CPU architectures.

## Supported Variants

### PHP Versions
- 8.5
- 8.4
- 8.3
- 8.2

### Debian Distributions
- Trixie (Debian 13)
- Bookworm (Debian 12)

### Architectures
- ARM64 (aarch64)
- AMD64 (x86_64)
- ARMv7 (32-bit ARM)

## Image Tags

Images are hosted on GitHub Container Registry with both multi-architecture manifests and architecture-specific tags.

### Multi-Architecture Manifests (Recommended)

**By PHP version only** (includes all available architectures):
```
ghcr.io/notglossy/frankenpress-src:php<version>
```

Examples:
- `ghcr.io/notglossy/frankenpress-src:php8.4` - All architectures across both distros
- `ghcr.io/notglossy/frankenpress-src:php8.3` - All architectures across both distros

**By PHP version + Debian version** (multi-arch for that distro):
```
ghcr.io/notglossy/frankenpress-src:php<version>-<debian>
```

Examples:
- `ghcr.io/notglossy/frankenpress-src:php8.4-trixie` - ARM64 + AMD64 on Trixie
- `ghcr.io/notglossy/frankenpress-src:php8.4-bookworm` - ARM64 + AMD64 + ARMv7 on Bookworm
- `ghcr.io/notglossy/frankenpress-src:php8.3-trixie` - ARM64 + AMD64 on Trixie

### Architecture-Specific Tags

For targeting specific Debian versions and architectures:
```
ghcr.io/notglossy/frankenpress-src:php<version>-<debian>-<arch>
```

Examples:
- `ghcr.io/notglossy/frankenpress-src:php8.4-trixie-amd64`
- `ghcr.io/notglossy/frankenpress-src:php8.3-bookworm-armv7`
- `ghcr.io/notglossy/frankenpress-src:php8.2-trixie-arm64`

Each architecture-specific image is also tagged with the git commit SHA:
- `ghcr.io/notglossy/frankenpress-src:php8.4-trixie-amd64-<git-sha>`

## Features

- Built with the latest Go compiler available in official Golang images
- Includes FrankenPHP with Caddy web server
- Compiled with optimized build flags
- Includes Vulcain and Brotli compression support
- File watcher library (libwatcher-c) for development
- Includes `install-php-extensions` helper for easy PHP extension installation
- **Supply chain security**: All images include SLSA provenance attestations and SBOMs

## Build Process

Images are automatically built using GitHub Actions on:
- Pushes to the `main` branch
- Pull requests (build only, no push - single test image)
- Manual workflow dispatch

The build process uses native architecture runners for optimal performance:
- AMD64 images: Built on `ubuntu-latest` (x86_64) runners
- ARM64/ARMv7 images: Built on `ubuntu-24.04-arm` (native ARM) runners

This eliminates the need for QEMU emulation and significantly speeds up ARM builds.

## Local Building

To build an image locally:

```bash
docker build \
  --build-arg PHP_VERSION=8.4 \
  --build-arg DEBIAN_VERSION=trixie \
  --platform linux/amd64 \
  -t frankenpress-base:local .
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
