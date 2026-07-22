#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    clang \
    clang-tidy \
    cmake \
    cppcheck \
    gdb \
    gcovr \
    lldb \
    ninja-build \
    pkg-config \
    valgrind
