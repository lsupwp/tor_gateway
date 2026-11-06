#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o tor-gateway .
echo "built: ./tor-gateway"
