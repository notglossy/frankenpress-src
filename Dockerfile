ARG PHP_VERSION=8.4
ARG DEBIAN_VERSION=trixie

FROM php:${PHP_VERSION}-zts-${DEBIAN_VERSION} AS php-base

FROM golang:${DEBIAN_VERSION} AS caddy-builder
# Copy PHP binaries, libraries and headers from the PHP image
COPY --from=php-base /usr/local/include /usr/local/include
COPY --from=php-base /usr/local/lib /usr/local/lib
COPY --from=php-base /usr/local/bin/php* /usr/local/bin/

# Install build dependencies (Debian usually has most of what you need)
RUN apt-get update && apt-get install -y \
    build-essential \
	libbrotli-dev \
	cmake \
	git \
	libreadline-dev \
	libncurses-dev \
	libxml2-dev \
	libssl-dev \
	zlib1g-dev \
	libsqlite3-dev \
	libcurl4-openssl-dev \
	libonig-dev \
	libargon2-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /

RUN git clone https://github.com/php/frankenphp.git \
	&& git clone https://github.com/e-dant/watcher.git

WORKDIR /watcher

RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
	&& cmake --build build \
	&& cmake --install build \
	&& cp /watcher/build/libwatcher-c.so /usr/local/lib/libwatcher-c.so \
	&& ldconfig	

WORKDIR /

RUN go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

# Set CGO flags using the copied php-config
ENV CGO_ENABLED=1
RUN export CGO_LDFLAGS="$(php-config --ldflags) $(php-config --libs)" \
	&& export CGO_CFLAGS="$(php-config --includes)" \
	&& export XCADDY_GO_BUILD_FLAGS="-ldflags='-w -s' -tags=nobadger,nomysql,nopgx" \
	&& xcaddy build \
	--output /usr/local/bin/frankenphp \
	--with github.com/dunglas/frankenphp/caddy \
	--with github.com/dunglas/vulcain/caddy \
	--with github.com/dunglas/caddy-cbrotli

FROM php:${PHP_VERSION}-zts-${DEBIAN_VERSION}

# Copy the built Caddy binary
COPY --from=caddy-builder /usr/local/bin/frankenphp /usr/local/bin/frankenphp
COPY --from=caddy-builder /usr/local/lib/libwatcher-c.so /usr/local/lib/libwatcher-c.so

WORKDIR /app
RUN ldconfig
RUN set -eux; \
	mkdir -p \
		/app/public \
		/config/caddy \
		/data/caddy \
		/etc/caddy \
		/etc/frankenphp; \
	sed -i 's/php/frankenphp run/g' /usr/local/bin/docker-php-entrypoint; \
	echo '<?php phpinfo();' > /app/public/index.php

COPY --from=caddy-builder /frankenphp/caddy/frankenphp/Caddyfile /etc/caddy/Caddyfile

RUN ln /etc/caddy/Caddyfile /etc/frankenphp/Caddyfile && \
	curl -sSLf \
		-o /usr/local/bin/install-php-extensions \
		https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions && \
	chmod +x /usr/local/bin/install-php-extensions

CMD ["--config", "/etc/frankenphp/Caddyfile", "--adapter", "caddyfile"]
HEALTHCHECK CMD curl -f http://localhost:2019/metrics || exit 1

# See https://caddyserver.com/docs/conventions#file-locations for details
ENV XDG_CONFIG_HOME=/config
ENV XDG_DATA_HOME=/data

EXPOSE 80
EXPOSE 443
EXPOSE 443/udp
EXPOSE 2019

LABEL org.opencontainers.image.title=FrankenPHP
LABEL org.opencontainers.image.description="The modern PHP app server"
LABEL org.opencontainers.image.url=https://github.com/notglossy/frankenpress-src
LABEL org.opencontainers.image.source=https://github.com/php/frankenphp
LABEL org.opencontainers.image.licenses=MIT
LABEL org.opencontainers.image.vendor="Not Glossy"