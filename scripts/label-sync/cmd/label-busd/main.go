// label-busd — the label-sync daemon. It (1) serves the optional bus.sock
// push socket, fanned out from ONE shared subscription, (2) runs the
// level-triggered reconcile loop (§11.4.233): reaps `done` entities past
// retention and republishes the snapshot (seq bump) whenever an entity
// transitions to stale, and (3) holds a single-instance flock plus a pidfile.
// Writers never depend on it: labelctl writes the state directory directly
// (and reaps opportunistically), so the system degrades to "no push socket,
// no time-driven stale publication", never to "no labels".
//
// Socket path: <dir>/bus.sock, or — when that exceeds the unix path limit —
// a short private fallback recorded in <dir>/bus.addr (CONTRACT §3).
//
// Exit codes: 0 clean shutdown; 2 cannot determine/start (state dir
// unusable, usage); 3 another instance already holds busd.lock (not an
// error of THIS instance: the daemon it would be is already up). Exit 1 is
// never used (it means "finding" in the labelctl convention).
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/bus"
	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/state"
)

// beforeListen is a test seam: called right before the socket is bound, so a
// test can widen the window in which a client may observe bus.addr.
var beforeListen = func() {}

// exitAlreadyRunning: another instance holds the single-instance lock.
const exitAlreadyRunning = 3

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	os.Exit(run(ctx, os.Args[1:], os.Stderr))
}

func run(ctx context.Context, args []string, errw io.Writer) int {
	opts := state.OptionsFromEnv()
	fs := flag.NewFlagSet("label-busd", flag.ContinueOnError)
	fs.SetOutput(errw)
	fs.StringVar(&opts.Dir, "dir", opts.Dir, "state directory")
	reconcile := fs.Duration("reconcile", time.Second, "reconcile interval")
	poll := fs.Duration("poll", 50*time.Millisecond, "socket fan-out poll interval")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	st, err := state.Open(opts)
	if err != nil {
		fmt.Fprintf(errw, "label-busd: %v\n", err)
		return 2
	}
	lock, err := state.TryLockFile(filepath.Join(st.Dir(), "busd.lock"))
	if err != nil {
		fmt.Fprintf(errw, "label-busd: another instance holds %s/busd.lock\n", st.Dir())
		return exitAlreadyRunning
	}
	defer lock.Close()
	pidf := filepath.Join(st.Dir(), "busd.pid")
	if err := state.WriteAtomic(pidf, []byte(strconv.Itoa(os.Getpid())+"\n")); err != nil {
		fmt.Fprintf(errw, "label-busd: %v\n", err)
		return 2
	}
	defer os.Remove(pidf)

	// Order (review-2 finding 6): bind the socket FIRST, record bus.addr only
	// once a client can actually dial it, and never leave an address behind
	// for a socket that was not bound (finding 14). A stale bus.addr from an
	// earlier crash is removed up front.
	addrf := filepath.Join(st.Dir(), bus.AddrFile)
	_ = os.Remove(addrf)
	srvDone := make(chan error, 1)
	sock, fallback, perr := bus.SocketPathFor(st.Dir())
	var ln net.Listener
	if perr == nil {
		beforeListen() // MUT:listenfirst
		ln, perr = bus.Listen(sock)
		if perr != nil {
			perr = fmt.Errorf("socket %s: %w", sock, perr)
		}
	}
	if perr == nil && fallback {
		if werr := state.WriteAtomic(addrf, []byte(sock+"\n")); werr != nil {
			_ = ln.Close()
			_ = os.Remove(sock)
			_ = os.Remove(addrf)
			perr = fmt.Errorf("cannot record %s: %w", addrf, werr)
		}
	}
	if perr != nil {
		fmt.Fprintf(errw, "label-busd: no socket (%v); reconcile loop only\n", perr)
		srvDone = nil
	} else {
		go func() { srvDone <- bus.ServeListener(ctx, st, ln, sock, *poll) }()
		defer func() {
			_ = os.Remove(addrf)
			if fallback {
				_ = os.Remove(filepath.Dir(sock)) // only succeeds when empty
			}
		}()
	}

	t := time.NewTicker(*reconcile)
	defer t.Stop()
	fmt.Fprintf(errw, "label-busd: up pid=%d dir=%s\n", os.Getpid(), st.Dir())
	for {
		select {
		case <-ctx.Done():
			if srvDone != nil {
				if err := <-srvDone; err != nil {
					fmt.Fprintf(errw, "label-busd: socket: %v\n", err)
				}
			}
			fmt.Fprintln(errw, "label-busd: clean shutdown")
			return 0
		case err := <-srvDone:
			// socket server ended on its own: keep reconciling, say so.
			fmt.Fprintf(errw, "label-busd: socket server stopped (%v); reconcile loop continues\n", err)
			srvDone = nil // a nil channel is never selected again
		case <-t.C:
			if _, _, err := st.Reconcile(); err != nil {
				fmt.Fprintf(errw, "label-busd: reconcile: %v\n", err)
			}
		}
	}
}
