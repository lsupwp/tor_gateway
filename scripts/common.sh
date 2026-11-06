#!/usr/bin/env bash
# Shared helpers for tor-gateway scripts. Sourced, not executed.

RUNDIR=/run/tor-gateway
TORRC=$RUNDIR/torrc
TOR_LOG=$RUNDIR/tor.log
STATUS_FILE=$RUNDIR/status
PID_FILE=$RUNDIR/tor.pid
SOCKS_PORT=9060
TRANS_PORT=9140
DNS_PORT=5453

IPT="iptables -w 5"
IP6T="ip6tables -w 5"

tor_user() {
    if id debian-tor >/dev/null 2>&1; then
        echo debian-tor
    elif id tor >/dev/null 2>&1; then
        echo tor
    else
        echo root
    fi
}

remove_rules() {
    for _ in $(seq 1 8); do
        $IPT -t nat -D OUTPUT -j TOR_GATEWAY_NAT 2>/dev/null || break
    done
    for _ in $(seq 1 8); do
        $IPT -D OUTPUT -j TOR_GATEWAY_OUT 2>/dev/null || break
    done
    for _ in $(seq 1 8); do
        $IP6T -D OUTPUT -j TOR_GATEWAY_OUT6 2>/dev/null || break
    done

    $IPT -t nat -F TOR_GATEWAY_NAT 2>/dev/null || true
    $IPT -t nat -X TOR_GATEWAY_NAT 2>/dev/null || true
    $IPT -F TOR_GATEWAY_OUT 2>/dev/null || true
    $IPT -X TOR_GATEWAY_OUT 2>/dev/null || true
    $IP6T -F TOR_GATEWAY_OUT6 2>/dev/null || true
    $IP6T -X TOR_GATEWAY_OUT6 2>/dev/null || true

    command -v conntrack >/dev/null 2>&1 && conntrack -F >/dev/null 2>&1 || true
}

add_rules() {
    local uid="$1"

    # Redirect locally generated TCP and DNS into Tor's transparent ports.
    $IPT -t nat -N TOR_GATEWAY_NAT
    $IPT -t nat -A TOR_GATEWAY_NAT -m owner --uid-owner "$uid" -j RETURN
    $IPT -t nat -A TOR_GATEWAY_NAT -p udp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"
    $IPT -t nat -A TOR_GATEWAY_NAT -d 127.0.0.0/8 -j RETURN
    $IPT -t nat -A TOR_GATEWAY_NAT -p tcp --syn -j REDIRECT --to-ports "$TRANS_PORT"
    $IPT -t nat -A OUTPUT -j TOR_GATEWAY_NAT

    # Drop anything that escaped the redirect, so no traffic leaks in the clear.
    $IPT -N TOR_GATEWAY_OUT
    $IPT -A TOR_GATEWAY_OUT -m owner --uid-owner "$uid" -j ACCEPT
    $IPT -A TOR_GATEWAY_OUT -o lo -j ACCEPT
    $IPT -A TOR_GATEWAY_OUT -d 127.0.0.0/8 -j ACCEPT
    $IPT -A TOR_GATEWAY_OUT -j REJECT --reject-with icmp-port-unreachable
    $IPT -I OUTPUT 1 -j TOR_GATEWAY_OUT

    # Block IPv6 entirely: Tor carries our traffic over IPv4 only.
    if $IP6T -L OUTPUT >/dev/null 2>&1; then
        $IP6T -N TOR_GATEWAY_OUT6
        $IP6T -A TOR_GATEWAY_OUT6 -o lo -j ACCEPT
        $IP6T -A TOR_GATEWAY_OUT6 -j REJECT
        $IP6T -I OUTPUT 1 -j TOR_GATEWAY_OUT6
    fi

    # Kill pre-existing flows so they cannot bypass the new rules.
    command -v conntrack >/dev/null 2>&1 && conntrack -F >/dev/null 2>&1 || true
}

stop_tor() {
    if [[ -f $PID_FILE ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null || true)
        if [[ -n ${pid:-} ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            for _ in $(seq 1 20); do
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.25
            done
            kill -9 "$pid" 2>/dev/null || true
        fi
        rm -f "$PID_FILE"
    fi
}

wait_bootstrap() {
    local deadline=$((SECONDS + 90))
    while ((SECONDS < deadline)); do
        if grep -q "Bootstrapped 100%" "$TOR_LOG" 2>/dev/null; then
            return 0
        fi
        if [[ -f $PID_FILE ]] && ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            return 1
        fi
        sleep 0.5
    done
    return 1
}
