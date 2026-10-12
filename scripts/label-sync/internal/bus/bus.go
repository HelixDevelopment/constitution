// Package bus is the real-time exchange layer of label-sync.
//
// Transport decision (see CONTRACT.md §3): the DURABLE bus is the state
// directory itself — events.jsonl plus the atomically rewritten `seq`
// counter. Any consumer (bash or Go, daemon or not) detects change by
// polling the tiny `seq` file (100-250 ms) and reads events newer than the
// last seq it saw. That works with plain bash and with the daemon down.
// The OPTIONAL accelerator is a unix socket served by label-busd that pushes
// the same events to Go subscribers with a ~50 ms bound. No inotify (not in
// the Go stdlib), no network.
package bus

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"sync"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/state"
)

// FromNow as a `since` value means "only events after the current head".
const FromNow = ^uint64(0)

// Subscribe polls the seq file every interval and delivers events with
// Seq > since in order, until ctx is cancelled (then the channel closes).
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
			if st.PeekSeq() > since {
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

type hello struct {
	Since uint64 `json:"since"`
}

type ack struct {
	Hello bool   `json:"hello"`
	Seq   uint64 `json:"seq"`
}

// Serve listens on a unix socket and pushes events to every subscriber.
// It refuses to start when a live server already owns the socket, replaces a
// stale socket file, and removes the socket on clean shutdown.
func Serve(ctx context.Context, st *state.Store, sockPath string, interval time.Duration) error {
	if c, err := net.DialTimeout("unix", sockPath, 300*time.Millisecond); err == nil {
		_ = c.Close()
		return fmt.Errorf("bus socket %s is owned by a live server", sockPath)
	}
	if fi, err := os.Lstat(sockPath); err == nil {
		if fi.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("refusing to replace symlink at %s", sockPath)
		}
		_ = os.Remove(sockPath)
	}
	ln, err := net.Listen("unix", sockPath)
	if err != nil {
		return err
	}
	_ = os.Chmod(sockPath, 0o600)
	var wg sync.WaitGroup
	go func() {
		<-ctx.Done()
		_ = ln.Close()
	}()
	for {
		conn, err := ln.Accept()
		if err != nil {
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
			serveConn(ctx, st, conn, interval)
		}()
	}
}

func serveConn(ctx context.Context, st *state.Store, conn net.Conn, interval time.Duration) {
	defer conn.Close()
	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil {
		return
	}
	var h hello
	if json.Unmarshal(line, &h) != nil {
		return
	}
	_ = conn.SetReadDeadline(time.Time{})
	if h.Since == FromNow {
		h.Since = st.PeekSeq()
	}
	enc := json.NewEncoder(conn)
	if enc.Encode(ack{Hello: true, Seq: h.Since}) != nil {
		return
	}
	cctx, cancel := context.WithCancel(ctx)
	defer cancel()
	// detect client hang-up
	go func() {
		_, _ = io.Copy(io.Discard, conn)
		cancel()
	}()
	for ev := range Subscribe(cctx, st, h.Since, interval) {
		_ = conn.SetWriteDeadline(time.Now().Add(2 * time.Second))
		if enc.Encode(ev) != nil {
			return
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
