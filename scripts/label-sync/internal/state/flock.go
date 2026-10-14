package state

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// ErrLockTimeout is returned when the state lock could not be acquired within
// the configured bound. Callers map it to "cannot determine" (exit 2).
var ErrLockTimeout = errors.New("state lock busy")

// lockFile is an flock(2)-based advisory lock on an open file description.
// Distinct Open()s (even in one process) conflict correctly.
type lockFile struct{ f *os.File }

// acquire takes the exclusive lock, waiting at most timeout (review: an
// unbounded LOCK_EX could hang a hook forever). The wait is a BLOCKING
// flock(2) in a helper goroutine, so waiters are queued by the kernel (no
// starvation, unlike sleep-polling). On timeout the helper is abandoned: if
// it later wins the lock it releases it at once and closes the fd. No child
// process is involved, so nothing is left behind.
func acquire(path string, timeout time.Duration) (*lockFile, error) {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, err
	}
	// fast path: uncontended
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err == nil { // MUT:flock
		return &lockFile{f: f}, nil
	}
	done := make(chan error, 1)
	go func() {
		var err error
		for {
			if err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != syscall.EINTR {
				break
			}
		}
		done <- err
	}()
	t := time.NewTimer(timeout) // MUT:locktimer
	defer t.Stop()
	select {
	case err := <-done:
		if err != nil {
			_ = f.Close()
			return nil, err
		}
		return &lockFile{f: f}, nil
	case <-t.C:
		go func() {
			if <-done == nil {
				_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
			}
			_ = f.Close()
		}()
		return nil, fmt.Errorf("%w for more than %v (%s held by another writer)", ErrLockTimeout, timeout, path)
	}
}

func (l *lockFile) release() {
	_ = syscall.Flock(int(l.f.Fd()), syscall.LOCK_UN)
	_ = l.f.Close()
}

// TryLockFile takes a non-blocking exclusive flock on path (used by the
// daemon for its single-instance pidfile lock). The returned file releases it
// on Close.
func TryLockFile(path string) (*os.File, error) {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = f.Close()
		return nil, err
	}
	return f, nil
}

// ProcPids is the production PidTable. On Linux a process is identified by
// pid PLUS its start time (/proc/<pid>/stat field 22, clock ticks since boot)
// PLUS the boot id, so a recycled pid is NOT mistaken for the registered
// process. Root defaults to /proc; Kill defaults to syscall.Kill (both are
// seams for a fake proc table in tests).
type ProcPids struct {
	Root string
	Kill func(pid int, sig syscall.Signal) error
}

func (p ProcPids) root() string {
	if p.Root == "" {
		return "/proc"
	}
	return p.Root
}

func (p ProcPids) kill(pid int) error {
	if p.Kill != nil {
		return p.Kill(pid, 0)
	}
	return syscall.Kill(pid, 0)
}

func (p ProcPids) bootID() (string, bool) {
	b, err := os.ReadFile(filepath.Join(p.root(), "sys", "kernel", "random", "boot_id"))
	if err != nil {
		return "", false
	}
	return strings.TrimSpace(string(b)), true
}

// starttime returns field 22 of /proc/<pid>/stat. The comm field (2) may
// contain spaces and parentheses, so fields are counted after the LAST ')'.
func (p ProcPids) starttime(pid int) (string, error) {
	b, err := os.ReadFile(filepath.Join(p.root(), fmt.Sprint(pid), "stat"))
	if err != nil {
		return "", err
	}
	s := string(b)
	i := strings.LastIndexByte(s, ')')
	if i < 0 {
		return "", errors.New("malformed stat")
	}
	f := strings.Fields(s[i+1:]) // f[0] is field 3 (state)
	if len(f) < 20 {
		return "", errors.New("short stat")
	}
	return f[19], nil // field 22
}

// NS returns this process's PID-namespace identity — the target of
// <root>/self/ns/pid, e.g. "pid:[4026531836]" — or "" when it cannot be read.
func (p ProcPids) NS() string {
	l, err := os.Readlink(filepath.Join(p.root(), "self", "ns", "pid"))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(l)
}

// Start returns "<boot_id>:<starttime>" for pid, or "" when unknowable.
func (p ProcPids) Start(pid int) string {
	if pid <= 0 {
		return ""
	}
	boot, ok := p.bootID()
	if !ok {
		return ""
	}
	st, err := p.starttime(pid)
	if err != nil {
		return ""
	}
	return boot + ":" + st
}

// Alive reports whether pid is (still) the registered process.
//   - /proc available: the pid's stat must exist; when start was recorded it
//     must match exactly (a recycled pid is NOT alive). A pid whose stat is
//     unreadable (hidepid) falls back to kill(pid,0): only nil counts, and
//     only when no start was recorded.
//   - no /proc: kill(pid,0)==nil is alive only when no start was recorded;
//     EPERM is never alive (its start cannot be matched).
func (p ProcPids) Alive(pid int, start string) bool {
	if pid <= 0 {
		return false
	}
	if _, ok := p.bootID(); ok {
		cur, err := p.starttime(pid)
		if err == nil {
			boot, _ := p.bootID()
			return start == "" || start == boot+":"+cur // MUT:pidstart
		}
		if errors.Is(err, os.ErrNotExist) {
			return false
		}
	}
	return start == "" && p.kill(pid) == nil
}
