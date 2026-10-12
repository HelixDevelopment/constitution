// label-busd — the label-sync daemon. It (1) serves the optional bus.sock
// push socket, (2) runs the level-triggered reconcile loop (§11.4.233):
// reaps `done` entities past retention and republishes the snapshot (seq
// bump) whenever an entity transitions to stale, and (3) holds a single-
// instance flock plus a pidfile. Writers never depend on it: labelctl writes
// the state directory directly, so the system degrades to "no push socket,
// no stale-transition publication", never to "no labels".
//
// Exit codes: 0 clean shutdown; 1 another instance is running; 2 cannot
// determine/start (state dir unusable).
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/bus"
	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/state"
)

func main() { os.Exit(run(os.Args[1:])) }

func run(args []string) int {
	opts := state.OptionsFromEnv()
	fs := flag.NewFlagSet("label-busd", flag.ContinueOnError)
	fs.StringVar(&opts.Dir, "dir", opts.Dir, "state directory")
	reconcile := fs.Duration("reconcile", time.Second, "reconcile interval")
	poll := fs.Duration("poll", 50*time.Millisecond, "socket fan-out poll interval")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	st, err := state.Open(opts)
	if err != nil {
		fmt.Fprintf(os.Stderr, "label-busd: %v\n", err)
		return 2
	}
	lock, err := state.TryLockFile(filepath.Join(st.Dir(), "busd.lock"))
	if err != nil {
		fmt.Fprintf(os.Stderr, "label-busd: another instance holds %s/busd.lock\n", st.Dir())
		return 1
	}
	defer lock.Close()
	pidf := filepath.Join(st.Dir(), "busd.pid")
	if err := state.WriteAtomic(pidf, []byte(strconv.Itoa(os.Getpid())+"\n")); err != nil {
		fmt.Fprintf(os.Stderr, "label-busd: %v\n", err)
		return 2
	}
	defer os.Remove(pidf)

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	srvDone := make(chan error, 1)
	go func() { srvDone <- bus.Serve(ctx, st, filepath.Join(st.Dir(), "bus.sock"), *poll) }()

	t := time.NewTicker(*reconcile)
	defer t.Stop()
	fmt.Fprintf(os.Stderr, "label-busd: up pid=%d dir=%s\n", os.Getpid(), st.Dir())
	for {
		select {
		case <-ctx.Done():
			if srvDone != nil {
				if err := <-srvDone; err != nil {
					fmt.Fprintf(os.Stderr, "label-busd: socket: %v\n", err)
				}
			}
			fmt.Fprintln(os.Stderr, "label-busd: clean shutdown")
			return 0
		case err := <-srvDone:
			// socket server ended on its own: keep reconciling, say so.
			fmt.Fprintf(os.Stderr, "label-busd: socket server stopped (%v); reconcile loop continues\n", err)
			srvDone = nil // a nil channel is never selected again
		case <-t.C:
			if _, _, err := st.Reconcile(); err != nil {
				fmt.Fprintf(os.Stderr, "label-busd: reconcile: %v\n", err)
			}
		}
	}
}
