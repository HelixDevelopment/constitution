package state

import (
	"errors"
	"os"
	"path/filepath"
	"syscall"
)

// fsyncFile is the ONE seam through which every durability fsync goes
// (temp files, the event log, directories). Tests replace it to count calls
// and to inject failures (review finding 9: "fsync removed" must be caught).
var fsyncFile = func(f *os.File) error { return f.Sync() }

// WriteAtomic replaces path with data using write-temp-then-rename in the
// SAME directory (rename(2) is atomic on POSIX filesystems): a reader sees
// either the complete old content or the complete new content, never a mix.
// The temp file is fsynced before the rename and the directory after it.
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
	f, err := os.CreateTemp(dir, "."+filepath.Base(path)+".tmp-*") // MUT:atomic
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
	if err := fsyncFile(f); err != nil { // MUT:tmpsync
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
	return syncDir(dir)
}

// syncDir fsyncs a directory so a rename/create in it is durable.
func syncDir(dir string) error {
	d, err := os.Open(dir)
	if err != nil {
		return err
	}
	defer d.Close()
	if err := fsyncFile(d); err != nil && !errors.Is(err, syscall.EINVAL) {
		return err
	}
	return nil
}
