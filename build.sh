#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build
mkdir -p build
javac -Xlint:all -d build $(find src -name '*.java')
jar --create --file build/tor-gateway.jar --main-class torgateway.TorGateway -C build torgateway
echo "built: build/tor-gateway.jar"
