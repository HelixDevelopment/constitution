package bus

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
)

// Finding 5(iv): N socket clients are served from ONE shared subscription —
// log reads do not scale with the number of clients.
func TestHubFansOutFromOneSubscription(t *testing.T) {
	s := newStore(t)
	sw(t, s, "a0")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	h := NewHub(s, 10*time.Millisecond)
	go h.Run(ctx)
	const clients = 12
	subs := make([]func(), 0, clients)
	recvs := make([]<-chan model.Event, 0, clients)
	for i := 0; i < clients; i++ {
		ch, c, _ := h.Subscribe(FromNow)
		subs = append(subs, c)
		recvs = append(recvs, ch)
	}
	for i := 1; i <= 5; i++ {
		sw(t, s, fmt.Sprintf("a%d", i))
	}
	for i, ch := range recvs {
		for want := uint64(2); want <= 6; want++ {
			if ev := recv(t, ch, 3*time.Second); ev.Seq != want {
				t.Fatalf("client %d got seq %d want %d", i, ev.Seq, want)
			}
		}
	}
	if r := h.Reads(); r > 5 {
		t.Fatalf("hub read the log %d times for 5 changes x %d clients (must not scale with clients)", r, clients)
	}
	for _, c := range subs {
		c()
	}
	// a late joiner gets its backlog from the ring, without a log read
	before := h.Reads()
	ch, c, _ := h.Subscribe(3)
	defer c()
	for want := uint64(4); want <= 6; want++ {
		if ev := recv(t, ch, 3*time.Second); ev.Seq != want {
			t.Fatalf("late joiner got %d want %d", ev.Seq, want)
		}
	}
	if h.Reads() != before {
		t.Fatalf("late joiner caused %d extra log reads", h.Reads()-before)
	}
}

// Finding 10: a state dir path that makes <dir>/bus.sock exceed the unix
// limit falls back to a short private path (0700 parent, 0600 socket) that
// clients find via bus.addr.
func TestLongStateDirFallsBackToShortSocket(t *testing.T) {
	base := t.TempDir()
	long := filepath.Join(base, strings.Repeat("d", 150-len(base)))
	if len(long) < 150 {
		t.Fatalf("test dir too short: %d", len(long))
	}
	if err := os.MkdirAll(long, 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XDG_RUNTIME_DIR", "")
	p, fb, err := SocketPathFor(long)
	if err != nil || !fb || len(p) > MaxSockPath {
		t.Fatalf("fallback: p=%q fb=%v err=%v", p, fb, err)
	}
	defer os.RemoveAll(filepath.Dir(p))
	fi, _ := os.Stat(filepath.Dir(p))
	if fi.Mode().Perm() != 0o700 {
		t.Fatalf("fallback dir mode %v", fi.Mode().Perm())
	}
	ln, err := Listen(p)
	if err != nil {
		t.Fatalf("listen on fallback: %v", err)
	}
	defer ln.Close()
	si, _ := os.Stat(p)
	if si.Mode().Perm() != 0o600 {
		t.Fatalf("socket mode %v, want 0600", si.Mode().Perm())
	}
	if err := os.WriteFile(filepath.Join(long, AddrFile), []byte(p+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := ResolveSocket(long); got != p {
		t.Fatalf("ResolveSocket = %q want %q", got, p)
	}
	short := t.TempDir()
	if got := ResolveSocket(short); got != filepath.Join(short, "bus.sock") {
		t.Fatalf("default resolve %q", got)
	}
	if p2, fb2, _ := SocketPathFor(short); fb2 || p2 != filepath.Join(short, "bus.sock") {
		t.Fatalf("short dir must not fall back: %q %v", p2, fb2)
	}
}
