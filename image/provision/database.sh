#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    mariadb-client \
    postgresql-client \
    sqlite3

mariadb --version
psql --version
sqlite3 --version
