package main

import (
	"fmt"
	"os"
	"runtime"
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
		err = cmdUp()
	case "down":
		err = cmdDown()
	case "status":
		cmdStatus()
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

func requireLinux() error {
	if runtime.GOOS != "linux" {
		return fmt.Errorf("this build supports Linux only (running on %s)", runtime.GOOS)
	}
	return nil
}

func requireRoot(command string) error {
	if err := requireLinux(); err != nil {
		return err
	}
	if os.Geteuid() != 0 {
		return fmt.Errorf("must run as root: sudo %s %s", prog, command)
	}
	return nil
}
