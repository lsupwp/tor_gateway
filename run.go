package main

import (
	"fmt"
	"os"
	"time"
)

func cmdUp() error {
	if err := requireRoot("up"); err != nil {
		return err
	}
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		return err
	}
	lock, err := acquireLock()
	if err != nil {
		return err
	}
	defer lock.Close()

	if isOpen() {
		fmt.Println("Tor routing is already open.")
		return nil
	}

	removeRules()
	stopTor()

	name, uid, gid, err := torUser()
	if err != nil {
		return err
	}
	fmt.Printf("tor user: %s (uid %d)\n", name, uid)

	_ = os.Chown(runDir, 0, gid)
	_ = os.Chmod(runDir, 0o775)
	chownTree(dataDir, uid, gid)

	torPath, err := findTor()
	if err != nil {
		return err
	}

	if err := os.WriteFile(torrc, []byte(torrcContent(name)), 0o644); err != nil {
		return err
	}
	if err := os.WriteFile(torLog, nil, 0o640); err != nil {
		return err
	}
	_ = os.Chown(torLog, uid, gid)
	writeStatus("")

	fmt.Println("validating config...")
	if err := verifyTorrc(torPath); err != nil {
		return err
	}

	fmt.Println("starting tor...")
	if err := startTor(torPath); err != nil {
		return err
	}

	fmt.Println("waiting for tor to bootstrap (up to 90s)...")
	if err := waitBootstrap(90 * time.Second); err != nil {
		stopTor()
		return err
	}
	fmt.Println("tor bootstrapped")

	fmt.Println("applying firewall rules...")
	if err := addRules(uid); err != nil {
		removeRules()
		stopTor()
		writeStatus("CLOSED")
		return err
	}
	writeStatus("OPEN")

	fmt.Printf(`Tor routing is OPEN
  SOCKS  127.0.0.1:%s
  Trans  127.0.0.1:%s
  DNS    127.0.0.1:%s
All TCP and DNS traffic now goes through Tor. UDP and ICMP are blocked.
`, socksPort, transPort, dnsPort)
	return nil
}

func cmdDown() error {
	if err := requireRoot("down"); err != nil {
		return err
	}
	if err := os.MkdirAll(runDir, 0o755); err != nil {
		return err
	}
	lock, err := acquireLock()
	if err != nil {
		return err
	}
	defer lock.Close()

	fmt.Println("removing firewall rules...")
	removeRules()

	fmt.Println("stopping tor...")
	stopTor()

	writeStatus("CLOSED")
	fmt.Println("Tor routing is CLOSED. Normal networking restored.")
	return nil
}
