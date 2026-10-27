package main

// Second-review fixes (findings 6 and 14 of the core/render/hooks review).

import (
	"bytes"
	"context"
	"errors"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/bus"
)

func longDir(t *testing.T) string {
	t.Helper()
	t.Setenv("XDG_RUNTIME_DIR", "")
	base := t.TempDir()
	dir := filepath.Join(base, strings.Repeat("y", max(10, 150-len(base))))
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	return dir
}

// Finding 6 (root cause): bus.addr was written BEFORE Listen, so a client that
// saw the file could dial a socket that did not exist yet. The seam widens the
// window to 400 ms: the address must never be observable before the socket.
func TestAddrRecordedOnlyAfterListen(t *testing.T) {
	old := beforeListen
	beforeListen = func() { time.Sleep(400 * time.Millisecond) }
	t.Cleanup(func() { beforeListen = old })
	dir := longDir(t)
	start(t, dir)
	addr := filepath.Join(dir, bus.AddrFile)
	waitFor(t, "bus.addr", func() bool { return exists(addr) })
	sock := bus.ResolveSocket(dir)
	c, err := net.DialTimeout("unix", sock, time.Second)
	if err != nil {
		t.Fatalf("bus.addr visible but socket %s not dialable: %v", sock, err)
	}
	_ = c.Close()
}

// Finding 14: a socket that cannot be bound must leave NO bus.addr behind
// (a stale address points clients at a path nobody serves).
func TestListenFailureLeavesNoAddr(t *testing.T) {
	dir := longDir(t)
	sock, fallback, err := bus.SocketPathFor(dir)
	if err != nil || !fallback {
		t.Fatalf("fixture: want a fallback socket path, got %q %v %v", sock, fallback, err)
	}
	t.Cleanup(func() { _ = os.Remove(sock); _ = os.Remove(filepath.Dir(sock)) })
	if err := os.Symlink(filepath.Join(t.TempDir(), "elsewhere"), sock); err != nil {
		t.Fatal(err)
	}
	d := start(t, dir)
	waitFor(t, "listen refusal logged", func() bool { return strings.Contains(d.log.String(), "reconcile loop only") })
	if exists(filepath.Join(dir, bus.AddrFile)) {
		t.Fatalf("bus.addr left behind although the socket was never bound (log: %s)", d.log.String())
	}
}

// Finding 14: a second instance exits with its OWN documented code (3), not
// the generic finding code 1.
func TestSecondInstanceExitCode(t *testing.T) {
	dir := t.TempDir()
	start(t, dir)
	waitFor(t, "pidfile", func() bool { return exists(filepath.Join(dir, "busd.pid")) })
	var e2 bytes.Buffer
	ctx, c := context.WithTimeout(context.Background(), 5*time.Second)
	defer c()
	if rc := run(ctx, []string{"--dir", dir}, &e2); rc != exitAlreadyRunning || exitAlreadyRunning != 3 {
		t.Fatalf("second instance rc=%d (%s), want 3", rc, e2.String())
	}
}

// Finding 14: the hello line is size-limited; a client streaming bytes with no
// newline is disconnected at the limit, not held for the 2 s read deadline.
func TestHelloLineIsSizeLimited(t *testing.T) {
	dir := t.TempDir()
	start(t, dir)
	waitFor(t, "socket", func() bool { return exists(bus.ResolveSocket(dir)) })
	c, err := net.DialTimeout("unix", bus.ResolveSocket(dir), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	t0 := time.Now()
	go func() { _, _ = c.Write(bytes.Repeat([]byte("x"), 64<<10)) }()
	_ = c.SetReadDeadline(time.Now().Add(5 * time.Second))
	buf := make([]byte, 16)
	_, rerr := c.Read(buf)
	if rerr == nil {
		t.Fatal("server answered an oversized hello")
	}
	if el := time.Since(t0); el > time.Second {
		t.Fatalf("oversized hello held the connection for %v (want a prompt close at the size limit)", el)
	}
}

// Re-review finding 10: a stale bus.addr from an earlier crash is removed up
// front. Observable when the socket then cannot be bound: nothing rewrites the
// file, so only the up-front removal keeps clients off a dead path.
func TestStaleAddrRemovedAtStart(t *testing.T) {
	dir := longDir(t)
	sock, fallback, err := bus.SocketPathFor(dir)
	if err != nil || !fallback {
		t.Fatalf("fixture: want a fallback socket path, got %q %v %v", sock, fallback, err)
	}
	t.Cleanup(func() { _ = os.Remove(sock); _ = os.Remove(filepath.Dir(sock)) })
	if err := os.Symlink(filepath.Join(t.TempDir(), "elsewhere"), sock); err != nil {
		t.Fatal(err)
	}
	addr := filepath.Join(dir, bus.AddrFile)
	if err := os.WriteFile(addr, []byte("/nonexistent/stale.sock\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	d := start(t, dir)
	waitFor(t, "listen refusal logged", func() bool { return strings.Contains(d.log.String(), "reconcile loop only") })
	if exists(addr) {
		t.Fatal("a stale bus.addr survived the daemon start (clients would dial a dead path)")
	}
}

// Re-review finding 10: when recording bus.addr fails AFTER the file was
// written (WriteAtomic's directory fsync), the address must be removed and
// the socket closed — never an address for a socket nobody serves.
func TestFailedAddrWriteLeavesNoAddr(t *testing.T) {
	old := writeAddr
	writeAddr = func(p string, b []byte) error {
		if err := os.WriteFile(p, b, 0o600); err != nil {
			return err
		}
		return errors.New("fsync dir: input/output error")
	}
	t.Cleanup(func() { writeAddr = old })
	dir := longDir(t)
	d := start(t, dir)
	waitFor(t, "record failure logged", func() bool { return strings.Contains(d.log.String(), "cannot record") })
	if exists(filepath.Join(dir, bus.AddrFile)) {
		t.Fatalf("bus.addr left behind after a failed record (log: %s)", d.log.String())
	}
}
