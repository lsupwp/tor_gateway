# Tor Gateway

Small Java desktop app with one large circular power button that routes all
TCP and DNS traffic on the machine through the Tor network. Red = direct
connection, green = routed through Tor. Click the button to toggle.

## Supported distributions

Linux only. Tested on **Kali GNU/Linux Rolling 2026.3** (Debian-based,
x86_64), kernel 7.1.5+kali-amd64, Tor 0.4.9.14.

| Distribution | Status | Notes |
|---|---|---|
| Kali Rolling | Tested | Reference platform |
| Debian 12/13 | Expected to work | Same packages and `debian-tor` user |
| Ubuntu 22.04+ / Mint / Parrot | Expected to work | Same as Debian |
| Arch / Manjaro | Expected to work | `pacman -S tor iptables polkit` |
| Fedora 39+ | Expected to work | `dnf install tor iptables-nft polkit` |
| openSUSE Tumbleweed | Untested | Needs `iptables` and a polkit agent |
| Alpine | Untested | No systemd needed, but install `polkit` and an agent |
| Windows / macOS | Not supported | Linux iptables required |

Portable across these because the app uses only Tor, iptables and pkexec.
No systemd dependency. The script auto-detects the Tor account
(`debian-tor`, `tor`, or root), so distro naming differences are handled.

## Requirements

- Linux with iptables/ip6tables (nft backend is fine)
- Java 17 or newer (`java`, `javac`)
- Tor (`sudo apt install tor`, or the distro equivalent)
- A polkit agent so `pkexec` can ask for your password (normal on desktop
  environments)

## Build and run

```sh
./build.sh
./run.sh
```

## What it does

Click the green button to start routing (or the red one to stop it). All
privileged work happens in the scripts:

**Start**

1. Starts a dedicated `tor` process with its own config under
   `/run/tor-gateway`.
   - SOCKS 9060, TransPort 9140, DNSPort 5453
   - TransPort runs with `IsolateDestAddr IsolateDestPort`, so streams to
     different destinations (host or port) use separate circuits. Tor then
     picks a different exit per circuit, so different sites usually show
     different exit IPs.
2. Waits until Tor reports `Bootstrapped 100%`.
3. Installs two iptables chains:
   - `TOR_GATEWAY_NAT` redirects all locally generated TCP to 9140 and
     UDP port 53 to 5453, except traffic owned by the Tor user.
   - `TOR_GATEWAY_OUT` accepts Tor's own traffic and loopback, then rejects
     everything else. This prevents leaks if a redirect fails.
4. Blocks all IPv6 output (Tor uses IPv4 here).

**Stop**

1. Removes the firewall chains.
2. Stops the Tor process.
3. Restores normal networking.

## Limitations

- Tor carries TCP only. UDP other than DNS is blocked, and ICMP (ping) is
  blocked, by design to prevent leaks.
- Local and link-local traffic is exempted only on loopback; private LAN
  destinations are routed through Tor.
- Apps with their own proxy settings may still work, but transparent
  redirect applies regardless.
- If the app is killed while routing is open, the rules stay active. Run
  `./scripts/tor-gateway-down.sh` as root to reset.
- Routes only the local machine, not other devices on the network.

## Files

```
build.sh                          compile to build/tor-gateway.jar
run.sh                            launch the GUI
src/main/java/torgateway/TorGateway.java
scripts/common.sh                 shared config and firewall helpers
scripts/tor-gateway-up.sh         start Tor + apply rules
scripts/tor-gateway-down.sh       stop Tor + remove rules
```
