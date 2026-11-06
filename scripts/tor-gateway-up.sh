#!/usr/bin/env bash
# Start Tor and route all TCP and DNS traffic through it.
# Requires root (invoked via pkexec by the GUI).
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

if [[ $EUID -ne 0 ]]; then
    echo "error: must run as root" >&2
    exit 1
fi

if ! command -v tor >/dev/null 2>&1; then
    echo "error: tor is not installed"
    echo "install it with: sudo apt install tor"
    exit 1
fi

mkdir -p "$RUNDIR"
chmod 755 "$RUNDIR"
exec 9>"$RUNDIR/lock"
if ! flock -n 9; then
    echo "error: another tor-gateway operation is in progress" >&2
    exit 1
fi

if [[ -f $STATUS_FILE ]] && [[ $(cat "$STATUS_FILE" 2>/dev/null) == OPEN ]]; then
    echo "Tor routing is already open."
    exit 0
fi

TOR_USER=$(tor_user)
TOR_UID=$(id -u "$TOR_USER")
echo "tor user: $TOR_USER (uid $TOR_UID)"

chown "root:$TOR_USER" "$RUNDIR" 2>/dev/null || true
chmod 775 "$RUNDIR"

mkdir -p "$RUNDIR/data"
chown -R "$TOR_USER" "$RUNDIR/data" 2>/dev/null || true
chmod 700 "$RUNDIR/data"

cat > "$TORRC" <<EOF
SocksPort 127.0.0.1:$SOCKS_PORT IsolateSOCKSAuth IsolateDestAddr IsolateDestPort
TransPort 127.0.0.1:$TRANS_PORT IsolateDestAddr IsolateDestPort
DNSPort 127.0.0.1:$DNS_PORT
HTTPTunnelPort 0
ClientOnly 1
SafeSocks 1
TestSocks 1
DisableAllSwap 1
DataDirectory $RUNDIR/data
User $TOR_USER
Log notice file $TOR_LOG
AutomapHostsOnResolve 1
VirtualAddrNetworkIPv4 10.192.0.0/10
EOF
chmod 644 "$TORRC"

: > "$TOR_LOG"
chown "$TOR_USER" "$TOR_LOG" 2>/dev/null || true
chmod 640 "$TOR_LOG"
: > "$STATUS_FILE"
chmod 644 "$STATUS_FILE"

cleanup() {
    echo "rolling back..."
    remove_rules || true
    stop_tor || true
    echo CLOSED > "$STATUS_FILE"
}
trap cleanup ERR

echo "validating config..."
if ! tor -f "$TORRC" --verify-config >/dev/null 2>"$RUNDIR/verify.log"; then
    echo "error: invalid torrc" >&2
    cat "$RUNDIR/verify.log" >&2
    false
fi

echo "starting tor..."
tor -f "$TORRC" --RunAsDaemon 1 --PidFile "$PID_FILE" 9>&- || {
    echo "error: tor failed to start" >&2
    tail -n 20 "$TOR_LOG" >&2 || true
    false
}

echo "waiting for tor to bootstrap (up to 90s)..."
if ! wait_bootstrap; then
    echo "error: tor did not bootstrap in time" >&2
    tail -n 20 "$TOR_LOG" >&2 || true
    false
fi
echo "tor bootstrapped"

echo "applying firewall rules..."
add_rules "$TOR_UID"

trap - ERR
echo OPEN > "$STATUS_FILE"
chmod 644 "$STATUS_FILE"
echo
echo "Tor routing is OPEN"
echo "  SOCKS  127.0.0.1:$SOCKS_PORT"
echo "  Trans  127.0.0.1:$TRANS_PORT"
echo "  DNS    127.0.0.1:$DNS_PORT"
echo "All TCP and DNS traffic now goes through Tor. UDP and ICMP are blocked."
