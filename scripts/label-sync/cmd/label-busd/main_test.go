package main

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/bus"
	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/state"
)

type syncBuf struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (s *syncBuf) Write(p []byte) (int, error) { s.mu.Lock(); defer s.mu.Unlock(); return s.b.Write(p) }
func (s *syncBuf) String() string               { s.mu.Lock(); defer s.mu.Unlock(); return s.b.String() }

type daemon struct {
	cancel context.CancelFunc
	rc     chan int
	log    *syncBuf
}

func start(t *testing.T, dir string, extra ...string) *daemon {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	d := &daemon{cancel: cancel, rc: make(chan int, 1), log: &syncBuf{}}
	args := append([]string{"--dir", dir, "--reconcile", "20ms", "--poll", "10ms"}, extra...)
	go func() { d.rc <- run(ctx, args, d.log) }()
	t.Cleanup(func() { cancel(); <-d.rc })
	return d
}

func waitFor(t *testing.T, what string, f func() bool) {
	t.Helper()
	for deadline := time.Now().Add(5 * time.Second); time.Now().Before(deadline); time.Sleep(10 * time.Millisecond) {
		if f() {
			return
		}
	}
	t.Fatalf("timeout waiting for %s", what)
}

func exists(p string) bool { _, err := os.Stat(p); return err == nil }

func store(t *testing.T, dir string) *state.Store {
	t.Helper()
	s, err := state.Open(state.Options{Dir: dir})
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestSingleInstanceAndCleanShutdown(t *testing.T) {
	dir := t.TempDir()
	d := start(t, dir)
	waitFor(t, "pidfile+socket", func() bool { return exists(filepath.Join(dir, "busd.pid")) && exists(bus.ResolveSocket(dir)) })
	sock := bus.ResolveSocket(dir)
	var e2 bytes.Buffer
	ctx2, c2 := context.WithTimeout(context.Background(), 5*time.Second)
	defer c2()
	if rc := run(ctx2, []string{"--dir", dir}, &e2); rc != exitAlreadyRunning {
		t.Fatalf("second instance rc=%d (%s), want %d", rc, e2.String(), exitAlreadyRunning)
	}
	d.cancel()
	select {
	case rc := <-d.rc:
		d.rc <- rc
		if rc != 0 {
			t.Fatalf("shutdown rc=%d log=%s", rc, d.log.String())
		}
	case <-time.After(5 * time.Second):
		t.Fatal("daemon did not shut down")
	}
	if exists(filepath.Join(dir, "busd.pid")) || exists(sock) || exists(filepath.Join(dir, bus.AddrFile)) {
		t.Fatal("clean shutdown must remove busd.pid and bus.sock")
	}
	if !strings.Contains(d.log.String(), "clean shutdown") {
		t.Fatalf("log: %s", d.log.String())
	}
}

func TestReconcileReapsAndPublishes(t *testing.T) {
	t.Setenv("LABEL_SYNC_DONE_RETENTION", "1ms")
	dir := t.TempDir()
	s := store(t, dir)
	e := model.Entity{ID: "gone", Kind: "command"}
	if _, err := s.Apply(model.Event{Type: model.EvRegister, Entity: &e}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Apply(model.Event{Type: model.EvUnregister, ID: "gone"}); err != nil {
		t.Fatal(err)
	}
	seq0 := s.PeekSeq()
	start(t, dir)
	waitFor(t, "reap by reconcile", func() bool {
		snap, err := s.Snapshot()
		return err == nil && len(snap.Entities) == 0 && s.PeekSeq() > seq0
	})
	if err := s.Verify(); err != nil {
		t.Fatal(err)
	}
}

func TestSocketFanOutToSeveralClients(t *testing.T) {
	dir := t.TempDir()
	s := store(t, dir)
	start(t, dir)
	waitFor(t, "socket", func() bool { return exists(bus.ResolveSocket(dir)) })
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var chs []<-chan model.Event
	for i := 0; i < 3; i++ {
		ch, cl, err := bus.Dial(ctx, bus.ResolveSocket(dir), bus.FromNow)
		if err != nil {
			t.Fatal(err)
		}
		defer cl.Close()
		chs = append(chs, ch)
	}
	if _, err := s.Apply(model.Event{Type: model.EvAliasSwitch, Active: &model.Active{Alias: "claude7"}}); err != nil {
		t.Fatal(err)
	}
	for i, ch := range chs {
		select {
		case ev := <-ch:
			if ev.Type != model.EvAliasSwitch || ev.Active.Alias != "claude7" {
				t.Fatalf("client %d got %+v", i, ev)
			}
		case <-time.After(5 * time.Second):
			t.Fatalf("client %d got nothing", i)
		}
	}
}

func TestLongStateDirUsesRecordedShortSocket(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", "")
	base := t.TempDir()
	dir := filepath.Join(base, strings.Repeat("x", max(10, 150-len(base))))
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	s := store(t, dir)
	d := start(t, dir)
	addr := filepath.Join(dir, bus.AddrFile)
	waitFor(t, "bus.addr", func() bool { return exists(addr) })
	sock := bus.ResolveSocket(dir)
	if len(sock) > bus.MaxSockPath || !exists(sock) {
		t.Fatalf("recorded socket %q unusable", sock)
	}
	if fi, _ := os.Stat(sock); fi.Mode().Perm() != 0o600 {
		t.Fatalf("socket mode %v", fi.Mode().Perm())
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	ch, cl, err := bus.Dial(ctx, sock, bus.FromNow)
	if err != nil {
		t.Fatalf("dial fallback: %v (log %s)", err, d.log.String())
	}
	defer cl.Close()
	if _, err := s.Apply(model.Event{Type: model.EvAliasSwitch, Active: &model.Active{Alias: "claude8"}}); err != nil {
		t.Fatal(err)
	}
	select {
	case ev := <-ch:
		if ev.Active == nil || ev.Active.Alias != "claude8" {
			t.Fatalf("got %+v", ev)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("no event over the fallback socket")
	}
	d.cancel()
	waitFor(t, "cleanup", func() bool { return !exists(addr) && !exists(sock) })
}
