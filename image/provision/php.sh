#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    composer \
    mariadb-client \
    php-cli \
    php-bcmath \
    php-curl \
    php-gd \
    php-intl \
    php-mbstring \
    php-mysql \
    php-sqlite3 \
    php-xml \
    php-zip

php --version
composer --version
