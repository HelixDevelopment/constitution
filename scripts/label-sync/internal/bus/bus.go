// Package bus is the real-time exchange layer of label-sync.
//
// Transport decision (see CONTRACT.md §3): the DURABLE bus is the state
// directory itself — events.jsonl plus the atomically rewritten `seq`
// counter. Any consumer (bash or Go, daemon or not) detects change by
// polling the tiny `seq` file (100-250 ms) and reads events newer than the
// last seq it saw. That works with plain bash and with the daemon down.
// The OPTIONAL accelerator is a unix socket served by label-busd that pushes
// the same events to Go subscribers with a ~50 ms bound, fanned out from ONE
// shared subscription (a hub). No inotify (not in the Go stdlib), no network.
package bus

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/state"
)

// FromNow as a `since` value means "only events after the current head".
const FromNow = ^uint64(0)

// MaxSockPath is the longest unix-socket path used directly. sun_path is 108
// bytes on Linux (104 on BSD/macOS) INCLUDING the NUL; a longer bind fails,
// so longer state dirs get a short private fallback (SocketPathFor).
const MaxSockPath = 100

// AddrFile is the file in the state dir that records the socket path the
// daemon actually listens on (present only when it is NOT <dir>/bus.sock).
const AddrFile = "bus.addr"

// Subscribe polls the seq file every interval and delivers events with
// Seq > since in order, until ctx is cancelled (then the channel closes).
// A subscriber that fell behind the compaction horizon first receives one
// synthetic `reconcile` event (re-read snapshot.json), then the tail.
func Subscribe(ctx context.Context, st *state.Store, since uint64, interval time.Duration) <-chan model.Event {
	out := make(chan model.Event, 64)
	if interval <= 0 {
		interval = 100 * time.Millisecond
	}
	go func() {
		defer close(out)
		if since == FromNow {
			since = st.PeekSeq()
		}
		t := time.NewTicker(interval)
		defer t.Stop()
		for {
			// seq absent (0) but a log present (pre-persist crash, legacy
			// dir): consult the log, else such events would never fire.
			if n := st.PeekSeq(); n > since || n == 0 { // MUT:peekzero
				evs, err := st.EventsSince(since)
				if err == nil {
					for _, ev := range evs {
						select {
						case out <- ev:
							since = ev.Seq
						case <-ctx.Done():
							return
						}
					}
				}
			}
			select {
			case <-ctx.Done():
				return
			case <-t.C:
			}
		}
	}()
	return out
}

// ------------------------------------------------------------ socket paths

func shortHash(s string) string {
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:6])
}

// privateDir creates (or validates) a 0700 directory owned by us; it refuses
// a symlink, a non-directory, or a directory owned by another uid.
func privateDir(d string) error {
	if err := os.Mkdir(d, 0o700); err != nil && !errors.Is(err, os.ErrExist) {
		return err
	}
	fi, err := os.Lstat(d)
	if err != nil {
		return err
	}
	if fi.Mode()&os.ModeSymlink != 0 || !fi.IsDir() {
		return fmt.Errorf("%s is not a real directory — refusing", d)
	}
	if st, ok := fi.Sys().(*syscall.Stat_t); ok && int(st.Uid) != os.Getuid() {
		return fmt.Errorf("%s is owned by uid %d — refusing", d, st.Uid)
	}
	if fi.Mode().Perm() != 0o700 {
		return os.Chmod(d, 0o700)
	}
	return nil
}

// SocketPathFor returns the socket path a daemon for state dir dir must use:
// <dir>/bus.sock when it fits, else a short private fallback —
// $XDG_RUNTIME_DIR/ls-<hash>/bus.sock, else /tmp/ls-<uid>-<hash>/bus.sock —
// whose parent is created 0700. fallback reports which.
func SocketPathFor(dir string) (path string, fallback bool, err error) {
	abs, err := filepath.Abs(dir)
	if err != nil {
		return "", false, err
	}
	direct := filepath.Join(abs, "bus.sock")
	if len(direct) <= MaxSockPath { // MUT:sockfallback
		return direct, false, nil
	}
	h := shortHash(abs)
	var cands []string
	if x := os.Getenv("XDG_RUNTIME_DIR"); x != "" && filepath.IsAbs(x) {
		cands = append(cands, filepath.Join(x, "ls-"+h))
	}
	cands = append(cands, filepath.Join(os.TempDir(), fmt.Sprintf("ls-%d-%s", os.Getuid(), h)))
	var last error
	for _, d := range cands {
		p := filepath.Join(d, "bus.sock")
		if len(p) > MaxSockPath {
			last = fmt.Errorf("fallback socket path %s too long", p)
			continue
		}
		if err := privateDir(d); err != nil {
			last = err
			continue
		}
		return p, true, nil
	}
	return "", true, fmt.Errorf("no usable socket path for %s: %v", abs, last)
}

// ResolveSocket returns the socket a client should dial for state dir dir:
// the path recorded in <dir>/bus.addr when present, else <dir>/bus.sock.
func ResolveSocket(dir string) string {
	if b, err := os.ReadFile(filepath.Join(dir, AddrFile)); err == nil {
		if p := strings.TrimSpace(string(b)); p != "" {
			return p
		}
	}
	return filepath.Join(dir, "bus.sock")
}

var umaskMu sync.Mutex

// Listen binds the unix socket. It refuses when a live server already owns
// it, refuses to replace a symlink, replaces a stale socket file, and creates
// the socket under umask 0177 so it is 0600 from birth (no chmod window).
func Listen(sockPath string) (net.Listener, error) {
	if len(sockPath) > 107 { // sun_path incl. NUL
		return nil, fmt.Errorf("socket path %d bytes exceeds the unix limit: %s", len(sockPath), sockPath)
	}
	if c, err := net.DialTimeout("unix", sockPath, 300*time.Millisecond); err == nil {
		_ = c.Close()
		return nil, fmt.Errorf("bus socket %s is owned by a live server", sockPath)
	}
	if fi, err := os.Lstat(sockPath); err == nil {
		if fi.Mode()&os.ModeSymlink != 0 {
			return nil, fmt.Errorf("refusing to replace symlink at %s", sockPath)
		}
		_ = os.Remove(sockPath)
	}
	umaskMu.Lock()
	old := syscall.Umask(0o177) // MUT:umask
	ln, err := net.Listen("unix", sockPath)
	syscall.Umask(old)
	umaskMu.Unlock()
	if err != nil {
		return nil, err
	}
	return ln, nil
}

// --------------------------------------------------------------------- hub

const (
	ringMax = 1024 // recent events kept for joining subscribers
	subBuf  = 1024 // per-subscriber buffer; a client that falls this far behind is dropped
)

type sub struct {
	ch    chan model.Event
	since uint64
}

// Hub is ONE shared subscription to the store fanned out to N subscribers
// (review finding 5(iv)): the store is polled and read once per change no
// matter how many clients are connected.
type Hub struct {
	st       *state.Store
	interval time.Duration
	mu       sync.Mutex
	pos      uint64
	ring     []model.Event
	subs     map[*sub]struct{}
	reads    int // EventsSince calls (observability, tests)
}

// NewHub returns a hub positioned at the current head.
func NewHub(st *state.Store, interval time.Duration) *Hub {
	if interval <= 0 {
		interval = 50 * time.Millisecond
	}
	return &Hub{st: st, interval: interval, pos: st.PeekSeq(), subs: map[*sub]struct{}{}}
}

// Reads reports how many times the hub read the event log.
func (h *Hub) Reads() int { h.mu.Lock(); defer h.mu.Unlock(); return h.reads }

// Run polls until ctx is done, then closes every subscriber.
func (h *Hub) Run(ctx context.Context) {
	t := time.NewTicker(h.interval)
	defer t.Stop()
	defer func() {
		h.mu.Lock()
		for s := range h.subs {
			close(s.ch)
			delete(h.subs, s)
		}
		h.mu.Unlock()
	}()
	for {
		h.poll()
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

func (h *Hub) poll() {
	h.mu.Lock()
	pos := h.pos
	h.mu.Unlock()
	if n := h.st.PeekSeq(); n != 0 && n <= pos {
		return
	}
	evs, err := h.st.EventsSince(pos)
	if err != nil {
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	h.reads++
	for _, ev := range evs {
		if ev.Seq <= h.pos {
			continue
		}
		h.pos = ev.Seq
		h.ring = append(h.ring, ev)
		if len(h.ring) > ringMax {
			h.ring = h.ring[len(h.ring)-ringMax:]
		}
		for s := range h.subs {
			if ev.Seq <= s.since {
				continue
			}
			select {
			case s.ch <- ev:
				s.since = ev.Seq
			default: // too slow: drop it; it may reconnect with since
				close(s.ch)
				delete(h.subs, s)
			}
		}
	}
}

// Subscribe joins the hub; events with Seq > since are delivered in order.
// Backlog comes from the ring when it covers since, else from ONE log read.
func (h *Hub) Subscribe(since uint64) (<-chan model.Event, func(), uint64) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if since == FromNow {
		since = h.pos
	}
	var backlog []model.Event
	if since < h.pos {
		if len(h.ring) > 0 && h.ring[0].Seq <= since+1 { // MUT:ring
			for _, ev := range h.ring {
				if ev.Seq > since {
					backlog = append(backlog, ev)
				}
			}
		} else if evs, err := h.st.EventsSince(since); err == nil {
			h.reads++
			for _, ev := range evs {
				if ev.Seq <= h.pos {
					backlog = append(backlog, ev)
				}
			}
		}
	}
	s := &sub{ch: make(chan model.Event, subBuf+len(backlog)), since: since}
	for _, ev := range backlog {
		s.ch <- ev
		s.since = ev.Seq
	}
	h.subs[s] = struct{}{}
	ack := since
	cancel := func() {
		h.mu.Lock()
		if _, ok := h.subs[s]; ok {
			delete(h.subs, s)
			close(s.ch)
		}
		h.mu.Unlock()
	}
	return s.ch, cancel, ack
}

// --------------------------------------------------------------- serving

type hello struct {
	Since uint64 `json:"since"`
}

type ack struct {
	Hello bool   `json:"hello"`
	Seq   uint64 `json:"seq"`
}

// Serve listens on sockPath and pushes events to every subscriber from one
// shared hub. It removes the socket on clean shutdown.
func Serve(ctx context.Context, st *state.Store, sockPath string, interval time.Duration) error {
	ln, err := Listen(sockPath)
	if err != nil {
		return err
	}
	return ServeListener(ctx, st, ln, sockPath, interval)
}

// ServeListener serves an already-bound listener (see Listen).
func ServeListener(ctx context.Context, st *state.Store, ln net.Listener, sockPath string, interval time.Duration) error {
	hctx, hcancel := context.WithCancel(ctx)
	defer hcancel()
	h := NewHub(st, interval)
	go h.Run(hctx)
	var wg sync.WaitGroup
	go func() {
		<-ctx.Done()
		_ = ln.Close()
	}()
	for {
		conn, err := ln.Accept()
		if err != nil {
			hcancel()
			wg.Wait()
			_ = os.Remove(sockPath)
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		wg.Add(1)
		go func() {
			defer wg.Done()
			serveConn(hctx, h, conn)
		}()
	}
}

func serveConn(ctx context.Context, h *Hub, conn net.Conn) {
	defer conn.Close()
	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil {
		return
	}
	var hl hello
	if json.Unmarshal(line, &hl) != nil {
		return
	}
	_ = conn.SetReadDeadline(time.Time{})
	ch, cancel, seq := h.Subscribe(hl.Since)
	defer cancel()
	enc := json.NewEncoder(conn)
	if enc.Encode(ack{Hello: true, Seq: seq}) != nil {
		return
	}
	cctx, ccancel := context.WithCancel(ctx)
	defer ccancel()
	go func() { // detect client hang-up
		_, _ = io.Copy(io.Discard, conn)
		ccancel()
	}()
	for {
		select {
		case <-cctx.Done():
			return
		case ev, ok := <-ch:
			if !ok {
				return
			}
			_ = conn.SetWriteDeadline(time.Now().Add(2 * time.Second))
			if enc.Encode(ev) != nil {
				return
			}
		}
	}
}

// Dial subscribes to a running label-busd. since may be FromNow. It returns
// after the server acknowledged the subscription (no lost-event race).
func Dial(ctx context.Context, sockPath string, since uint64) (<-chan model.Event, io.Closer, error) {
	conn, err := net.DialTimeout("unix", sockPath, 2*time.Second)
	if err != nil {
		return nil, nil, err
	}
	if err := json.NewEncoder(conn).Encode(hello{Since: since}); err != nil {
		_ = conn.Close()
		return nil, nil, err
	}
	br := bufio.NewReader(conn)
	_ = conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	line, err := br.ReadBytes('\n')
	if err != nil {
		_ = conn.Close()
		return nil, nil, err
	}
	var a ack
	if json.Unmarshal(line, &a) != nil || !a.Hello {
		_ = conn.Close()
		return nil, nil, errors.New("bus: bad handshake")
	}
	_ = conn.SetReadDeadline(time.Time{})
	out := make(chan model.Event, 64)
	go func() {
		defer close(out)
		go func() { <-ctx.Done(); _ = conn.Close() }()
		for {
			l, err := br.ReadBytes('\n')
			if err != nil {
				return
			}
			var ev model.Event
			if json.Unmarshal(l, &ev) != nil {
				continue
			}
			select {
			case out <- ev:
			case <-ctx.Done():
				return
			}
		}
	}()
	return out, conn, nil
}
