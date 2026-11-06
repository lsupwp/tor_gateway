#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -f build/tor-gateway.jar ]]; then
    ./build.sh
fi
exec java -Dtor.gateway.home="$PWD" -jar build/tor-gateway.jar
