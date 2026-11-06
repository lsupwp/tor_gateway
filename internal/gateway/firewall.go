package gateway

import (
	"errors"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

func hasCmd(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

func runCmd(name string, args ...string) error {
	out, err := exec.Command(name, args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s %s: %v: %s", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return nil
}

func ipt(args ...string) error {
	return runCmd("iptables", append([]string{"-w", "5"}, args...)...)
}

func ip6(args ...string) error {
	return runCmd("ip6tables", append([]string{"-w", "5"}, args...)...)
}

func addRules(uid int) error {
	if !hasCmd("iptables") {
		return errors.New("iptables not found (install the iptables package)")
	}
	removeRules()

	u := strconv.Itoa(uid)

	natRules := [][]string{
		{"-t", "nat", "-N", "TOR_GATEWAY_NAT"},
		{"-t", "nat", "-A", "TOR_GATEWAY_NAT", "-m", "owner", "--uid-owner", u, "-j", "RETURN"},
		{"-t", "nat", "-A", "TOR_GATEWAY_NAT", "-p", "udp", "--dport", "53", "-j", "REDIRECT", "--to-ports", dnsPort},
		{"-t", "nat", "-A", "TOR_GATEWAY_NAT", "-d", "127.0.0.0/8", "-j", "RETURN"},
		{"-t", "nat", "-A", "TOR_GATEWAY_NAT", "-p", "tcp", "--syn", "-j", "REDIRECT", "--to-ports", transPort},
		{"-t", "nat", "-A", "OUTPUT", "-j", "TOR_GATEWAY_NAT"},
	}
	for _, rule := range natRules {
		if err := ipt(rule...); err != nil {
			return err
		}
	}

	filterRules := [][]string{
		{"-N", "TOR_GATEWAY_OUT"},
		{"-A", "TOR_GATEWAY_OUT", "-m", "owner", "--uid-owner", u, "-j", "ACCEPT"},
		{"-A", "TOR_GATEWAY_OUT", "-o", "lo", "-j", "ACCEPT"},
		{"-A", "TOR_GATEWAY_OUT", "-d", "127.0.0.0/8", "-j", "ACCEPT"},
		{"-A", "TOR_GATEWAY_OUT", "-j", "REJECT", "--reject-with", "icmp-port-unreachable"},
		{"-I", "OUTPUT", "1", "-j", "TOR_GATEWAY_OUT"},
	}
	for _, rule := range filterRules {
		if err := ipt(rule...); err != nil {
			return err
		}
	}

	if hasCmd("ip6tables") {
		ipv6Rules := [][]string{
			{"-N", "TOR_GATEWAY_OUT6"},
			{"-A", "TOR_GATEWAY_OUT6", "-o", "lo", "-j", "ACCEPT"},
			{"-A", "TOR_GATEWAY_OUT6", "-j", "REJECT"},
			{"-I", "OUTPUT", "1", "-j", "TOR_GATEWAY_OUT6"},
		}
		for _, rule := range ipv6Rules {
			if err := ip6(rule...); err != nil {
				return err
			}
		}
	}

	flushConntrack()
	return nil
}

func removeRules() {
	for i := 0; i < 8; i++ {
		if ipt("-t", "nat", "-D", "OUTPUT", "-j", "TOR_GATEWAY_NAT") != nil {
			break
		}
	}
	for i := 0; i < 8; i++ {
		if ipt("-D", "OUTPUT", "-j", "TOR_GATEWAY_OUT") != nil {
			break
		}
	}
	for i := 0; i < 8; i++ {
		if ip6("-D", "OUTPUT", "-j", "TOR_GATEWAY_OUT6") != nil {
			break
		}
	}

	_ = ipt("-t", "nat", "-F", "TOR_GATEWAY_NAT")
	_ = ipt("-t", "nat", "-X", "TOR_GATEWAY_NAT")
	_ = ipt("-F", "TOR_GATEWAY_OUT")
	_ = ipt("-X", "TOR_GATEWAY_OUT")
	_ = ip6("-F", "TOR_GATEWAY_OUT6")
	_ = ip6("-X", "TOR_GATEWAY_OUT6")

	flushConntrack()
}

func flushConntrack() {
	if hasCmd("conntrack") {
		_ = runCmd("conntrack", "-F")
	}
}
