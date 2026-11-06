package main

import (
	"fmt"
	"os"

	"github.com/lsupwp/tor_gateway/internal/gateway"
)

const (
	version = "1.0.0"
	prog    = "tor-gateway"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	var err error
	switch os.Args[1] {
	case "up":
		err = gateway.Up()
	case "down":
		err = gateway.Down()
	case "status":
		if gateway.IsOpen() {
			fmt.Println("OPEN")
		} else {
			fmt.Println("CLOSED")
		}
	case "version", "--version", "-v":
		fmt.Printf("%s %s\n", prog, version)
	case "help", "--help", "-h":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "unknown command %q\n\n", os.Args[1])
		usage()
		os.Exit(2)
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, `%s %s - route all TCP and DNS traffic through Tor

Usage:
  sudo %s up       start Tor and apply routing rules
  sudo %s down     stop Tor and restore normal networking
       %s status   show current state
       %s version  print version

Requires Linux, tor, iptables and root for up/down.
`, prog, version, prog, prog, prog, prog)
}
