#!/usr/bin/env bash
# Build and install tor-gateway.
# Usage: sudo ./install.sh            build, install deps, install binary
#        ./install.sh --build-only    build the binary only, no root needed
set -euo pipefail
cd "$(dirname "$0")"

BIN=tor-gateway
PREFIX=/usr/local/bin
MODE=install

case "${1:-}" in
    "") ;;
    --build-only) MODE=build ;;
    -h|--help)
        echo "usage: sudo ./install.sh [--build-only]"
        exit 0
        ;;
    *) echo "error: unknown option $1" >&2; exit 2 ;;
esac

die() {
    echo "error: $*" >&2
    exit 1
}

if [[ $MODE == install && $EUID -ne 0 ]]; then
    die "run as root: sudo ./install.sh (or use --build-only)"
fi

build() {
    if ! command -v go >/dev/null 2>&1; then
        if [[ -x $BIN ]]; then
            echo "Go not found, using existing $BIN"
            return
        fi
        die "Go is required to build $BIN"
    fi
    echo "building $BIN..."
    CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o "$BIN" ./cmd/tor-gateway
    if [[ $EUID -eq 0 && -n ${SUDO_USER:-} ]]; then
        chown "$SUDO_USER":"$(id -gn "$SUDO_USER")" "$BIN" 2>/dev/null || true
    fi
}

install_packages() {
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq || true
        apt-get install -y tor iptables conntrack
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y tor iptables-nft conntrack-tools
    elif command -v pacman >/dev/null 2>&1; then
        pacman -S --needed --noconfirm tor iptables conntrack-tools
    elif command -v zypper >/dev/null 2>&1; then
        zypper --non-interactive install tor iptables conntrack-tools
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache tor iptables conntrack-tools
    else
        die "no supported package manager found (apt, dnf, pacman, zypper, apk)"
    fi
}

install_conntrack() {
    if command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y conntrack
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y conntrack-tools
    elif command -v pacman >/dev/null 2>&1; then
        pacman -S --needed --noconfirm conntrack-tools
    elif command -v zypper >/dev/null 2>&1; then
        zypper --non-interactive install conntrack-tools
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache conntrack-tools
    fi
}

build
[[ $MODE == build ]] && exit 0

missing=0
command -v tor >/dev/null 2>&1 || missing=1
command -v iptables >/dev/null 2>&1 || missing=1
command -v ip6tables >/dev/null 2>&1 || missing=1

if [[ $missing -eq 1 ]]; then
    echo "installing tor and iptables..."
    install_packages
else
    echo "tor and iptables already present."
fi

# conntrack is optional: without it, old flows are not flushed on start.
if ! command -v conntrack >/dev/null 2>&1; then
    echo "installing conntrack (optional)..."
    install_conntrack >/dev/null 2>&1 || echo "warning: could not install conntrack"
fi

command -v tor >/dev/null 2>&1 || die "tor is still missing after install"
command -v iptables >/dev/null 2>&1 || die "iptables is still missing after install"

install -m 755 "$BIN" "$PREFIX/tor-gateway"

# sudo often uses a restricted secure_path that omits /usr/local/bin.
# Add a symlink in /usr/bin when that is the case.
if [[ ":$PATH:" != *":$PREFIX:"* ]]; then
    ln -sf "$PREFIX/tor-gateway" /usr/bin/tor-gateway
fi

echo
echo "installed: $PREFIX/tor-gateway"
echo "start:     sudo tor-gateway up"
echo "stop:      sudo tor-gateway down"
echo "state:     tor-gateway status"
