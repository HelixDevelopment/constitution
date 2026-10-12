package state

import (
	"errors"
	"os"
	"path/filepath"
)

// WriteAtomic replaces path with data using write-temp-then-rename in the
// SAME directory (rename(2) is atomic on POSIX filesystems): a reader sees
// either the complete old content or the complete new content, never a mix.
func WriteAtomic(path string, data []byte) error {
	return writeAtomic(path, data, 0o600, false)
}

// errSimulatedTorn is returned by the failMid test hook.
var errSimulatedTorn = errors.New("simulated torn write")

// writeAtomic is WriteAtomic plus a test hook: failMid writes the first half
// of data to the temp file and aborts, simulating a kill -9 mid-write. The
// destination must be untouched in that case.
func writeAtomic(path string, data []byte, perm os.FileMode, failMid bool) error {
	dir := filepath.Dir(path)
	f, err := os.CreateTemp(dir, "."+filepath.Base(path)+".tmp-*")
	if err != nil {
		return err
	}
	tmp := f.Name()
	cleanup := func() { _ = os.Remove(tmp) }
	if failMid {
		_, _ = f.Write(data[:len(data)/2])
		_ = f.Close()
		cleanup()
		return errSimulatedTorn
	}
	if _, err := f.Write(data); err != nil {
		_ = f.Close()
		cleanup()
		return err
	}
	if err := f.Chmod(perm); err != nil {
		_ = f.Close()
		cleanup()
		return err
	}
	if err := f.Sync(); err != nil {
		_ = f.Close()
		cleanup()
		return err
	}
	if err := f.Close(); err != nil {
		cleanup()
		return err
	}
	if err := os.Rename(tmp, path); err != nil {
		cleanup()
		return err
	}
	if d, err := os.Open(dir); err == nil {
		_ = d.Sync()
		_ = d.Close()
	}
	return nil
}
