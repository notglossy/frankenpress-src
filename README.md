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

Use these tags to automatically pull the correct architecture for your platform:
```
ghcr.io/notglossy/frankenpress-src:php<version>
```

Each manifest includes:
- Trixie: ARM64 + AMD64
- Bookworm: ARMv7

Examples:
- `ghcr.io/notglossy/frankenpress-src:php8.4` (auto-selects architecture)
- `ghcr.io/notglossy/frankenpress-src:php8.3` (auto-selects architecture)
- `ghcr.io/notglossy/frankenpress-src:php8.2` (auto-selects architecture)

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

## Build Process

Images are automatically built using GitHub Actions on:
- Pushes to the `main` branch
- Pull requests (build only, no push)
- Manual workflow dispatch

The build process uses Docker Buildx with QEMU for cross-platform compilation, enabling ARM builds on x86 runners.

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

## Usage in FrankenPress

These base images are consumed by the [FrankenPress](https://github.com/notglossy/frankenpress) project to create production-ready WordPress hosting environments.

## License

MIT
