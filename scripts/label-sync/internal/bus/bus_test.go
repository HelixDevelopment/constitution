package bus

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/state"
)

type noPids struct{}

func (noPids) Alive(int, string) bool { return false }
func (noPids) Start(int) string       { return "" }

func newStore(t *testing.T) *state.Store {
	t.Helper()
	s, err := state.Open(state.Options{Dir: t.TempDir(), Pids: noPids{}, TTL: time.Hour})
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func sw(t *testing.T, s *state.Store, alias string) {
	t.Helper()
	if _, err := s.Apply(model.Event{Type: model.EvAliasSwitch, Active: &model.Active{Alias: alias, Model: "m", Effort: "e"}}); err != nil {
		t.Fatal(err)
	}
}

func recv(t *testing.T, ch <-chan model.Event, d time.Duration) model.Event {
	t.Helper()
	select {
	case ev, ok := <-ch:
		if !ok {
			t.Fatal("channel closed")
		}
		return ev
	case <-time.After(d):
		t.Fatal("timeout waiting for event")
	}
	return model.Event{}
}

func TestSubscribePollsSeqInOrder(t *testing.T) {
	s := newStore(t)
	sw(t, s, "a0")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	ch := Subscribe(ctx, s, 0, 20*time.Millisecond) // replays from 0
	if ev := recv(t, ch, 2*time.Second); ev.Seq != 1 || ev.Active.Alias != "a0" {
		t.Fatalf("replay: %+v", ev)
	}
	sw(t, s, "a1")
	sw(t, s, "a2")
	if ev := recv(t, ch, 2*time.Second); ev.Seq != 2 {
		t.Fatalf("got %+v", ev)
	}
	if ev := recv(t, ch, 2*time.Second); ev.Seq != 3 {
		t.Fatalf("got %+v", ev)
	}
	cancel()
	select {
	case _, ok := <-ch:
		if ok {
			// drain one in flight, then must close
			if _, ok2 := <-ch; ok2 {
				t.Fatal("channel not closed after cancel")
			}
		}
	case <-time.After(2 * time.Second):
		t.Fatal("channel not closed after cancel")
	}
}

func TestSubscribeSinceSkipsOld(t *testing.T) {
	s := newStore(t)
	sw(t, s, "a")
	sw(t, s, "b")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	ch := Subscribe(ctx, s, 1, 20*time.Millisecond)
	if ev := recv(t, ch, 2*time.Second); ev.Seq != 2 {
		t.Fatalf("got %+v", ev)
	}
}

func TestSocketFanOutAndLatency(t *testing.T) {
	s := newStore(t)
	sock, _, err := SocketPathFor(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	srvErr := make(chan error, 1)
	go func() { srvErr <- Serve(ctx, s, sock, 20*time.Millisecond) }()
	waitFor(t, func() bool { _, err := os.Stat(sock); return err == nil })

	c1, cl1, err := Dial(ctx, sock, ^uint64(0)) // "from now"
	if err != nil {
		t.Fatal(err)
	}
	defer cl1.Close()
	c2, cl2, err := Dial(ctx, sock, ^uint64(0))
	if err != nil {
		t.Fatal(err)
	}
	defer cl2.Close()
	time.Sleep(100 * time.Millisecond)
	start := time.Now()
	sw(t, s, "claude3")
	for i, c := range []<-chan model.Event{c1, c2} {
		ev := recv(t, c, 2*time.Second)
		if ev.Type != model.EvAliasSwitch || ev.Active.Alias != "claude3" {
			t.Fatalf("sub %d got %+v", i, ev)
		}
	}
	if d := time.Since(start); d > time.Second {
		t.Fatalf("propagation too slow: %v", d)
	}
	// replay from a past seq
	c3, cl3, err := Dial(ctx, sock, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer cl3.Close()
	if ev := recv(t, c3, 2*time.Second); ev.Seq != 1 {
		t.Fatalf("replay got %+v", ev)
	}
	// a dropped subscriber must not stop the server
	cl1.Close()
	sw(t, s, "claude4")
	if ev := recv(t, c2, 2*time.Second); ev.Active.Alias != "claude4" {
		t.Fatalf("got %+v", ev)
	}
	cancel()
	select {
	case <-srvErr:
	case <-time.After(3 * time.Second):
		t.Fatal("server did not shut down on cancel")
	}
	if _, err := os.Stat(sock); err == nil {
		t.Fatal("socket file must be removed on clean shutdown")
	}
}

func TestServeRefusesLiveSocketReplacesStale(t *testing.T) {
	s := newStore(t)
	sock, _, err := SocketPathFor(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	// stale: a plain file where the socket should be
	if err := os.WriteFile(sock, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go Serve(ctx, s, sock, 20*time.Millisecond)
	waitFor(t, func() bool { c, _, err := Dial(ctx, sock, ^uint64(0)); return err == nil && c != nil })
	ctx2, cancel2 := context.WithCancel(context.Background())
	defer cancel2()
	if err := Serve(ctx2, s, sock, 20*time.Millisecond); err == nil {
		t.Fatal("second server on a live socket must fail")
	}
}

func waitFor(t *testing.T, f func() bool) {
	t.Helper()
	for i := 0; i < 100; i++ {
		if f() {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("condition not reached")
}
