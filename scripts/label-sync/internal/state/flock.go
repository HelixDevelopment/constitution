package state

import (
	"os"
	"syscall"
)

// lockFile is an flock(2)-based advisory lock on an open file description.
// Distinct Open()s (even in one process) conflict correctly.
type lockFile struct{ f *os.File }

func acquire(path string) (*lockFile, error) {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, err
	}
	for {
		err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX)
		if err != syscall.EINTR {
			break
		}
	}
	if err != nil {
		_ = f.Close()
		return nil, err
	}
	return &lockFile{f: f}, nil
}

func (l *lockFile) release() {
	_ = syscall.Flock(int(l.f.Fd()), syscall.LOCK_UN)
	_ = l.f.Close()
}

// TryLockFile takes a non-blocking exclusive flock on path (used by the
// daemon for its single-instance pidfile lock). The returned func releases it.
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

// ProcPids is the production PidTable: kill(pid, 0).
type ProcPids struct{}

// Alive reports whether pid exists (EPERM counts as alive).
func (ProcPids) Alive(pid int) bool {
	if pid <= 0 {
		return false
	}
	err := syscall.Kill(pid, 0)
	return err == nil || err == syscall.EPERM
}
