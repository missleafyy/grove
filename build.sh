#!/bin/sh
# Rebuild the Grove engine binary into bin/grove.
cd "$(dirname "$0")"
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release >/dev/null && cmake --build build -j"$(nproc)"
