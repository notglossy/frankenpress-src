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
# FrankenPHP release (e.g. v1.13.3); "latest" resolves the newest tag at build time.
ARG FRANKENPHP_VERSION=latest

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
		gnupg \
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

# Fetch the latest patch release of PHP_VERSION, verify its checksum, and
# verify its GPG signature was made by one of that branch's release managers.
# The fingerprints are pinned here (same as docker-library/php), so a
# compromised php.net can't substitute its own key; php.net's keyring is only
# used to obtain the public keys.
RUN set -eux; \
	case "$PHP_VERSION" in \
		8.2) keys='39B641343D8C104B2B146DC3F9C39DC0B9698544 E60913E4DF209907D8E30D96659A97C9CF2A795A 1198C0117593497A5EC5C199286AF1F9897469DC' ;; \
		8.3) keys='1198C0117593497A5EC5C199286AF1F9897469DC C28D937575603EB4ABB725861C0779DC5C0A9DE4 AFD8691FDAEDF03BDF6E460563F15A9B715376CA' ;; \
		8.4) keys='AFD8691FDAEDF03BDF6E460563F15A9B715376CA 9D7F99A0CB8F05C8A6958D6256A97AF7600A39A6 0616E93D95AF471243E26761770426E17EBBB3DD' ;; \
		8.5) keys='1198C0117593497A5EC5C199286AF1F9897469DC 49D9AF6BC72A80D6691719C8AA23F5BE9C7097D4 D95C03BC702BE9515344AE3374E44BC9067701A5' ;; \
		*) echo >&2 "No release-manager GPG keys pinned for PHP $PHP_VERSION"; exit 1 ;; \
	esac; \
	release="$(curl -fsSL "https://www.php.net/releases/?json&version=${PHP_VERSION}")"; \
	version="$(echo "$release" | jq -r .version)"; \
	sha256="$(echo "$release" | jq -r '.source[] | select(.filename | endswith(".tar.xz")) | .sha256')"; \
	curl -fsSLo /tmp/php.tar.xz "https://www.php.net/distributions/php-${version}.tar.xz"; \
	curl -fsSLo /tmp/php.tar.xz.asc "https://www.php.net/distributions/php-${version}.tar.xz.asc"; \
	echo "${sha256}  /tmp/php.tar.xz" | sha256sum -c -; \
	export GNUPGHOME="$(mktemp -d)"; \
	curl -fsSL https://www.php.net/distributions/php-keyring.gpg | gpg --batch --import; \
	signer="$(gpg --batch --status-fd 1 --verify /tmp/php.tar.xz.asc /tmp/php.tar.xz | awk '$2 == "VALIDSIG" { print $NF }')"; \
	case " $keys " in \
		*" $signer "*) echo "PHP $version signed by $signer" ;; \
		*) echo >&2 "PHP $version signed by unexpected key '$signer'"; exit 1 ;; \
	esac; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME" /tmp/php.tar.xz.asc; \
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

# Resolve one FrankenPHP release, so the binary and the default Caddyfile come
# from the same tag.
ARG FRANKENPHP_VERSION
WORKDIR /src
RUN set -eux; \
	version="$FRANKENPHP_VERSION"; \
	if [ "$version" = latest ]; then \
		version="$(go list -m -f '{{.Version}}' github.com/dunglas/frankenphp/caddy@latest)"; \
	fi; \
	echo "$version" > /src/frankenphp-version; \
	git clone --depth 1 --branch "$version" https://github.com/php/frankenphp.git; \
	git clone --depth 1 https://github.com/e-dant/watcher.git

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
		--with "github.com/dunglas/frankenphp/caddy@$(cat /src/frankenphp-version)" \
		--with github.com/dunglas/vulcain/caddy \
		--with github.com/dunglas/caddy-cbrotli \
	&& rm -rf /root/go /root/.cache \
	&& frankenphp version

COPY --from=runtime-base /var/lib/dpkg/status.d /usr/local/share/frankenpress/base-status.d
COPY fp-collect-runtime /usr/local/bin/fp-collect-runtime

# Directories and default config shared by both targets. /skel is root-owned
# (config, webroot); /skel-state holds the only paths the server writes to.
# /etc/frankenphp/Caddyfile is a symlink, so overriding either path works.
RUN set -eux; \
	mkdir -p /skel/app/public /skel/etc/caddy /skel/etc/frankenphp /skel-state/config/caddy /skel-state/data/caddy; \
	echo '<?php phpinfo();' > /skel/app/public/index.php; \
	cp /src/frankenphp/caddy/frankenphp/Caddyfile /skel/etc/caddy/Caddyfile; \
	ln -s ../caddy/Caddyfile /skel/etc/frankenphp/Caddyfile

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
RUN cp -a /skel/. /skel-state/. / && rm -rf /skel /skel-state /src
WORKDIR /app
ENV XDG_CONFIG_HOME=/config \
	XDG_DATA_HOME=/data
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile", "--adapter", "caddyfile"]

# -----------------------------------------------------------------------------
# runtime: clean DHI base + PHP + FrankenPHP
# -----------------------------------------------------------------------------
FROM runtime-base AS runtime

COPY --from=collect /rootfs/ /
COPY --from=collect /skel/ /
COPY --from=collect --chown=65532:65532 /skel-state/ /

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
