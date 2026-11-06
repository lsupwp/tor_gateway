package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

func timeSleep(ms int) {
	time.Sleep(time.Duration(ms) * time.Millisecond)
}

func findTor() (string, error) {
	path, err := exec.LookPath("tor")
	if err != nil {
		return "", fmt.Errorf("tor not installed (install the tor package)")
	}
	return path, nil
}

func torrcContent(userName string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "SocksPort 127.0.0.1:%s IsolateSOCKSAuth IsolateDestAddr IsolateDestPort\n", socksPort)
	fmt.Fprintf(&b, "TransPort 127.0.0.1:%s IsolateDestAddr IsolateDestPort\n", transPort)
	fmt.Fprintf(&b, "DNSPort 127.0.0.1:%s\n", dnsPort)
	b.WriteString("HTTPTunnelPort 0\n")
	b.WriteString("ClientOnly 1\n")
	b.WriteString("SafeSocks 1\n")
	b.WriteString("TestSocks 1\n")
	b.WriteString("DisableAllSwap 1\n")
	fmt.Fprintf(&b, "DataDirectory %s\n", dataDir)
	if userName != "root" {
		fmt.Fprintf(&b, "User %s\n", userName)
	}
	fmt.Fprintf(&b, "Log notice file %s\n", torLog)
	b.WriteString("AutomapHostsOnResolve 1\n")
	b.WriteString("VirtualAddrNetworkIPv4 10.192.0.0/10\n")
	return b.String()
}

func verifyTorrc(torPath string) error {
	out, err := exec.Command(torPath, "-f", torrc, "--verify-config").CombinedOutput()
	if err != nil {
		return fmt.Errorf("invalid torrc: %s", strings.TrimSpace(string(out)))
	}
	return nil
}

func startTor(torPath string) error {
	cmd := exec.Command(torPath, "-f", torrc, "--RunAsDaemon", "1", "--PidFile", pidFile)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("tor failed to start: %s", strings.TrimSpace(string(out)))
	}
	return nil
}

func waitBootstrap(timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		data, _ := os.ReadFile(torLog)
		if strings.Contains(string(data), "Bootstrapped 100%") {
			return nil
		}
		if pid, err := readPid(); err == nil && !pidAlive(pid) {
			return fmt.Errorf("tor exited during startup:\n%s", tail(string(data), 12))
		}
		timeSleep(500)
	}
	data, _ := os.ReadFile(torLog)
	return fmt.Errorf("tor did not bootstrap within %s:\n%s", timeout, tail(string(data), 12))
}

func tail(s string, lines int) string {
	parts := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if len(parts) > lines {
		parts = parts[len(parts)-lines:]
	}
	return strings.Join(parts, "\n")
}
