#!/usr/bin/env bash
# Stop Tor and remove the transparent routing firewall rules.
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

mkdir -p "$RUNDIR"
exec 9>"$RUNDIR/lock"
if ! flock -n 9; then
    echo "error: another tor-gateway operation is in progress" >&2
    exit 1
fi

echo "removing firewall rules..."
remove_rules

echo "stopping tor..."
stop_tor

echo CLOSED > "$STATUS_FILE" 2>/dev/null || true
chmod 644 "$STATUS_FILE" 2>/dev/null || true

echo
echo "Tor routing is CLOSED. Normal networking restored."
