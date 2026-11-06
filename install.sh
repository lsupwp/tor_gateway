#!/usr/bin/env bash
# Install runtime dependencies and the tor-gateway binary.
# Usage: sudo ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

BIN=tor-gateway
PREFIX=/usr/local/bin

die() {
    echo "error: $*" >&2
    exit 1
}

if [[ $EUID -ne 0 ]]; then
    die "run as root: sudo ./install.sh"
fi

# Build the binary if it is not there yet.
if [[ ! -x $BIN ]]; then
    if ! command -v go >/dev/null 2>&1; then
        die "$BIN not built and Go is not installed. Run ./build.sh first."
    fi
    echo "building $BIN..."
    ./build.sh
    if [[ -n ${SUDO_USER:-} ]]; then
        chown "$SUDO_USER":"$(id -gn "$SUDO_USER")" "$BIN" 2>/dev/null || true
    fi
fi

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
echo
echo "installed: $PREFIX/tor-gateway"
echo "start:     sudo tor-gateway up"
echo "stop:      sudo tor-gateway down"
echo "state:     tor-gateway status"
