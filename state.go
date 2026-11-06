package main

import (
	"errors"
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

const (
	runDir   = "/run/tor-gateway"
	dataDir  = runDir + "/data"
	torrc    = runDir + "/torrc"
	torLog   = runDir + "/tor.log"
	pidFile  = runDir + "/tor.pid"
	status   = runDir + "/status"
	lockFile = runDir + "/lock"

	socksPort = "9060"
	transPort = "9140"
	dnsPort   = "5453"
)

func acquireLock() (*os.File, error) {
	f, err := os.OpenFile(lockFile, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		f.Close()
		return nil, errors.New("another operation is in progress")
	}
	return f, nil
}

func torUser() (name string, uid, gid int, err error) {
	for _, candidate := range []string{"debian-tor", "tor"} {
		u, lookupErr := user.Lookup(candidate)
		if lookupErr != nil {
			continue
		}
		uid, _ = strconv.Atoi(u.Uid)
		gid, _ = strconv.Atoi(u.Gid)
		return candidate, uid, gid, nil
	}
	if os.Geteuid() == 0 {
		return "root", 0, 0, nil
	}
	return "", -1, -1, errors.New("no tor system user found (looked for debian-tor and tor)")
}

func chownTree(root string, uid, gid int) {
	filepath.WalkDir(root, func(path string, _ os.DirEntry, err error) error {
		if err == nil {
			_ = os.Chown(path, uid, gid)
		}
		return nil
	})
}

func writeStatus(value string) {
	_ = os.WriteFile(status, []byte(value+"\n"), 0o644)
}

func readPid() (int, error) {
	b, err := os.ReadFile(pidFile)
	if err != nil {
		return 0, err
	}
	return strconv.Atoi(strings.TrimSpace(string(b)))
}

func pidAlive(pid int) bool {
	return syscall.Kill(pid, 0) == nil
}

func isOpen() bool {
	b, err := os.ReadFile(status)
	if err != nil || strings.TrimSpace(string(b)) != "OPEN" {
		return false
	}
	pid, err := readPid()
	if err != nil {
		return false
	}
	comm, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/comm")
	return err == nil && strings.TrimSpace(string(comm)) == "tor"
}

func stopTor() {
	pid, err := readPid()
	if err == nil && pidAlive(pid) {
		_ = syscall.Kill(pid, syscall.SIGTERM)
		for i := 0; i < 20; i++ {
			if !pidAlive(pid) {
				break
			}
			timeSleep(250)
		}
		if pidAlive(pid) {
			_ = syscall.Kill(pid, syscall.SIGKILL)
		}
	}
	_ = os.Remove(pidFile)
}

func cmdStatus() {
	if isOpen() {
		fmt.Println("OPEN")
		return
	}
	fmt.Println("CLOSED")
}
