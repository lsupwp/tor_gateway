# Tor Gateway

Command-line tool that routes all TCP and DNS traffic on the machine through
the Tor network, with a built-in kill switch. Written in Go, ships as one
static binary.

## Requirements

- Linux with `iptables` / `ip6tables` (nft backend is fine)
- Tor (`tor` package)
- Root for `up` and `down`

The binary has no runtime dependencies. Go is needed only to build it.

## Build

```sh
./build.sh
```

Or directly:

```sh
CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o tor-gateway ./cmd/tor-gateway
```

Result: single statically linked executable, about 2 MB.

Install:

```sh
sudo ./install.sh
```

`install.sh` detects the package manager (apt, dnf, pacman, zypper, apk),
installs `tor`, `iptables` and `conntrack`, builds the binary if missing,
and copies it to `/usr/local/bin/tor-gateway`.

## Usage

```sh
sudo tor-gateway up       # start Tor and route all TCP/DNS traffic
sudo tor-gateway down     # stop Tor and restore normal networking
tor-gateway status        # print OPEN or CLOSED (no root needed)
tor-gateway version
```

Example:

```sh
$ sudo tor-gateway up
tor user: debian-tor (uid 117)
validating config...
starting tor...
waiting for tor to bootstrap (up to 90s)...
tor bootstrapped
applying firewall rules...
Tor routing is OPEN
  SOCKS  127.0.0.1:9060
  Trans  127.0.0.1:9140
  DNS    127.0.0.1:5453
```

## What it does

1. Writes a dedicated `torrc` under `/run/tor-gateway` with:
   - `SocksPort 127.0.0.1:9060` with `IsolateSOCKSAuth IsolateDestAddr
     IsolateDestPort`
   - `TransPort 127.0.0.1:9140` with `IsolateDestAddr IsolateDestPort`
   - `DNSPort 127.0.0.1:5453`
   - `HTTPTunnelPort 0`, `ClientOnly 1`
   - `SafeSocks 1`, `TestSocks 1`
   - `DisableAllSwap 1`
2. Starts `tor` and waits for `Bootstrapped 100%`.
3. Adds iptables chains:
   - `TOR_GATEWAY_NAT` redirects all locally generated TCP to 9140 and
     UDP port 53 to 5453, except traffic owned by the Tor user.
   - `TOR_GATEWAY_OUT` accepts Tor's own traffic and loopback, then rejects
     everything else. This is the kill switch.
4. Blocks all IPv6 output.
5. Flushes conntrack so pre-existing flows cannot bypass the redirect.

`down` removes the chains, stops Tor, and restores normal networking.

## Supported distributions

Linux only. Tested on **Kali GNU/Linux Rolling 2026.3** (Debian-based,
x86_64), kernel 7.1.5+kali-amd64, Tor 0.4.9.14.

| Distribution | Status | Notes |
|---|---|---|
| Kali Rolling | Tested | Reference platform |
| Debian 12/13 | Expected to work | Same packages and `debian-tor` user |
| Ubuntu 22.04+ / Mint / Parrot | Expected to work | Same as Debian |
| Arch / Manjaro | Expected to work | `pacman -S tor iptables` |
| Fedora 39+ | Expected to work | `dnf install tor iptables-nft` |
| openSUSE Tumbleweed | Untested | Needs `iptables` |
| Alpine | Untested | Install `iptables` and `tor` |
| Windows / macOS | Not supported | Linux iptables required |

No systemd dependency. The Tor account is auto-detected (`debian-tor`,
`tor`, or root).

## Cross-compiling

Go builds per target OS; it is not one binary for all systems:

```sh
GOOS=linux   GOARCH=amd64 CGO_ENABLED=0 go build -o tor-gateway-linux-amd64 ./cmd/tor-gateway
GOOS=linux   GOARCH=arm64 CGO_ENABLED=0 go build -o tor-gateway-linux-arm64 ./cmd/tor-gateway
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -o tor-gateway.exe ./cmd/tor-gateway
GOOS=darwin  GOARCH=arm64 CGO_ENABLED=0 go build -o tor-gateway-macos ./cmd/tor-gateway
```

The tool refuses to run outside Linux, because transparent routing needs
Linux iptables.

## Limitations

- Tor carries TCP only. UDP other than DNS and ICMP are blocked to prevent
  leaks.
- Opening routing kills existing connections, because conntrack is flushed.
- Private LAN destinations are routed through Tor; only loopback is exempt.
- Routes only the local machine.
- If the process is killed while open, rules stay active. Run
  `sudo tor-gateway down` to reset.

## Files

```
cmd/tor-gateway/main.go        CLI entry point and argument parsing
internal/gateway/run.go        up/down commands
internal/gateway/tor.go        torrc generation, process start, bootstrap wait
internal/gateway/firewall.go   iptables rules, conntrack flush
internal/gateway/state.go      paths, locking, tor user detection, status
build.sh                       static build helper
install.sh                     dependency install + binary install
```
