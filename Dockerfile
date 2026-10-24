# syntax=docker/dockerfile:1
#
# FrankenPHP on Docker Hardened Images (dhi.io).
#
# DHI has no thread-safe (ZTS) PHP, so PHP is compiled here from the official
# source tarball against DHI's own Debian packages (dhi.io/deb). FrankenPHP is
# built with DHI's Go toolchain. The runtime target copies only what is needed
# onto a clean dhi.io/debian-base image (non-root, no apt).
#
# Targets:
#   runtime (default) - minimal image for running apps
#   dev               - full build environment with PIE, for compiling extensions
#
# Requires `docker login dhi.io`.

ARG PHP_VERSION=8.4

FROM dhi.io/debian-base:trixie AS runtime-base
FROM dhi.io/golang:1-debian13-dev AS golang
FROM ghcr.io/php/pie:bin AS pie

# -----------------------------------------------------------------------------
# Builder: ZTS PHP, libwatcher and FrankenPHP
# -----------------------------------------------------------------------------
FROM dhi.io/debian-base:trixie-dev AS builder
ARG PHP_VERSION

ENV PHP_INI_DIR=/usr/local/etc/php

RUN apt-get update && apt-get install -y --no-install-recommends \
		autoconf \
		bison \
		ca-certificates \
		cmake \
		curl \
		dpkg-dev \
		file \
		g++ \
		gcc \
		git \
		jq \
		libc-dev \
		libcap2-bin \
		make \
		pkg-config \
		re2c \
		unzip \
		xz-utils \
		libargon2-dev \
		libbrotli-dev \
		libcurl4-openssl-dev \
		libffi-dev \
		libfreetype-dev \
		libicu-dev \
		libjpeg62-turbo-dev \
		libonig-dev \
		libpng-dev \
		libsodium-dev \
		libsqlite3-dev \
		libssl-dev \
		libwebp-dev \
		libxml2-dev \
		libzip-dev \
		zlib1g-dev \
	&& rm -rf /var/lib/apt/lists/*

# Fetch the latest patch release of PHP_VERSION and verify its checksum.
RUN set -eux; \
	release="$(curl -fsSL "https://www.php.net/releases/?json&version=${PHP_VERSION}")"; \
	version="$(echo "$release" | jq -r .version)"; \
	sha256="$(echo "$release" | jq -r '.source[] | select(.filename | endswith(".tar.xz")) | .sha256')"; \
	curl -fsSLo /tmp/php.tar.xz "https://www.php.net/distributions/php-${version}.tar.xz"; \
	echo "${sha256}  /tmp/php.tar.xz" | sha256sum -c -; \
	mkdir -p /usr/src/php; \
	tar -xJf /tmp/php.tar.xz -C /usr/src/php --strip-components=1; \
	rm /tmp/php.tar.xz

# Bundled extensions WordPress commonly needs are built as shared modules but
# not enabled; enable them with an ini file (extension=gd). PECL extensions are
# installed with PIE in the dev target.
RUN set -eux; \
	cd /usr/src/php; \
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
	debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
	./configure \
		--build="$gnuArch" \
		--prefix=/usr/local \
		--with-config-file-path="$PHP_INI_DIR" \
		--with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
		--enable-option-checking=fatal \
		--with-libdir="lib/$debMultiarch" \
		--with-pic \
		--enable-zts \
		--enable-embed \
		--disable-zend-signals \
		--enable-zend-max-execution-timers \
		--disable-cgi \
		--disable-phpdbg \
		--enable-mbstring \
		--enable-mysqlnd \
		--with-password-argon2 \
		--with-sodium=shared \
		--with-pdo-sqlite=/usr \
		--with-sqlite3=/usr \
		--with-curl \
		--with-iconv \
		--with-openssl \
		--with-zlib \
		--enable-bcmath=shared \
		--enable-exif=shared \
		--enable-gd=shared --with-freetype --with-jpeg --with-webp \
		--enable-intl=shared \
		--with-mysqli=shared \
		--with-pdo-mysql=shared \
		--with-zip=shared \
		--with-ffi=shared \
	; \
	make -j "$(nproc)"; \
	make install; \
	find /usr/local/bin /usr/local/lib -type f -exec sh -c 'file -b "$1" | grep -q "^ELF"' _ {} \; -exec strip --strip-unneeded {} +; \
	mkdir -p "$PHP_INI_DIR/conf.d"; \
	cp php.ini-production php.ini-development "$PHP_INI_DIR/"; \
	echo 'extension=sodium' > "$PHP_INI_DIR/conf.d/sodium.ini"; \
	if [ -f "$(php-config --extension-dir)/opcache.so" ]; then \
		echo 'zend_extension=opcache' > "$PHP_INI_DIR/conf.d/opcache.ini"; \
	fi; \
	cd /; rm -rf /usr/src/php; \
	php -v; php -m

COPY --from=golang /usr/lib/go /usr/lib/go
ENV PATH=/usr/lib/go/bin:/root/go/bin:$PATH \
	CGO_ENABLED=1

WORKDIR /src
RUN git clone --depth 1 https://github.com/php/frankenphp.git \
	&& git clone --depth 1 https://github.com/e-dant/watcher.git

RUN cmake -S watcher -B watcher/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-Wno-error=use-after-free" \
	&& cmake --build watcher/build \
	&& cmake --install watcher/build \
	&& ldconfig

# rpath lets FrankenPHP find libphp/libwatcher in /usr/local/lib on a runtime
# image that has no ldconfig.
RUN go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest \
	&& export CGO_CFLAGS="$(php-config --includes)" \
	&& export CGO_LDFLAGS="$(php-config --ldflags) $(php-config --libs) -L/usr/local/lib -Wl,-rpath,/usr/local/lib" \
	&& export XCADDY_GO_BUILD_FLAGS="-ldflags='-w -s' -tags=nobadger,nomysql,nopgx" \
	&& xcaddy build \
		--output /usr/local/bin/frankenphp \
		--with github.com/dunglas/frankenphp/caddy \
		--with github.com/dunglas/vulcain/caddy \
		--with github.com/dunglas/caddy-cbrotli \
	&& rm -rf /root/go /root/.cache \
	&& frankenphp version

COPY --from=runtime-base /var/lib/dpkg/status.d /usr/local/share/frankenpress/base-status.d
COPY fp-collect-runtime /usr/local/bin/fp-collect-runtime

# Directories and default config shared by both targets.
RUN set -eux; \
	mkdir -p /skel/app/public /skel/config/caddy /skel/data/caddy /skel/etc/caddy /skel/etc/frankenphp; \
	echo '<?php phpinfo();' > /skel/app/public/index.php; \
	cp /src/frankenphp/caddy/frankenphp/Caddyfile /skel/etc/frankenphp/Caddyfile; \
	cp /src/frankenphp/caddy/frankenphp/Caddyfile /skel/etc/caddy/Caddyfile

# -----------------------------------------------------------------------------
# Collect the runtime filesystem
# -----------------------------------------------------------------------------
FROM builder AS collect
RUN fp-collect-runtime /rootfs \
	&& cd /rootfs \
	&& find usr/local -type f -print0 | xargs -0 sha256sum > /runtime-usr-local.sha256

# -----------------------------------------------------------------------------
# dev: build environment with PIE for compiling extensions
# -----------------------------------------------------------------------------
# Downstream images compile extensions here, then copy the result onto the
# runtime image:
#
#   FROM ghcr.io/notglossy/frankenpress-src:php8.4-dev AS build
#   RUN apt-get update && apt-get install -y libmagickwand-dev \
#       && pie install imagick/imagick phpredis/phpredis \
#       && fp-collect-runtime /rootfs
#   FROM ghcr.io/notglossy/frankenpress-src:php8.4
#   COPY --from=build /rootfs/ /
FROM builder AS dev
COPY --from=pie /pie /usr/local/bin/pie
# Tell fp-collect-runtime what the runtime image already contains.
COPY --from=collect /rootfs/var/lib/dpkg/status.d/ /usr/local/share/frankenpress/base-status.d/
COPY --from=collect /runtime-usr-local.sha256 /usr/local/share/frankenpress/
RUN cp -a /skel/. / && rm -rf /skel /src
WORKDIR /app
ENV XDG_CONFIG_HOME=/config \
	XDG_DATA_HOME=/data
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile", "--adapter", "caddyfile"]

# -----------------------------------------------------------------------------
# runtime: clean DHI base + PHP + FrankenPHP
# -----------------------------------------------------------------------------
FROM runtime-base AS runtime

COPY --from=collect /rootfs/ /
COPY --from=collect --chown=65532:65532 /skel/ /

ENV PHP_INI_DIR=/usr/local/etc/php \
	XDG_CONFIG_HOME=/config \
	XDG_DATA_HOME=/data

WORKDIR /app
USER 65532

EXPOSE 80
EXPOSE 443
EXPOSE 443/udp
EXPOSE 2019

HEALTHCHECK CMD ["php", "-r", "exit(@file_get_contents('http://localhost:2019/metrics') === false ? 1 : 0);"]
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile", "--adapter", "caddyfile"]

LABEL org.opencontainers.image.title=FrankenPHP \
	org.opencontainers.image.description="FrankenPHP on Docker Hardened Images" \
	org.opencontainers.image.url=https://github.com/notglossy/frankenpress-src \
	org.opencontainers.image.source=https://github.com/notglossy/frankenpress-src \
	org.opencontainers.image.licenses=MIT \
	org.opencontainers.image.vendor="Not Glossy"
