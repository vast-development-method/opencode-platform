#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/php.sh"
"$SCRIPT_DIR/python.sh"
"$SCRIPT_DIR/cpp.sh"
"$SCRIPT_DIR/typescript.sh"
apt-get install -y --no-install-recommends openjdk-21-jdk
