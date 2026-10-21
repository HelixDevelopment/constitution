// labelctl — command-line client of the constitution label-sync system
// (§11.4.182 labels + §11.4.116-style real-time sync). See
// docs/label-sync/CONTRACT.md and docs/label-sync/README.md.
//
// Exit codes: 0 success; 1 finding (unknown id, verify problem, invalid
// input); 2 cannot determine (state dir unusable, usage error). 2 is never a
// pass.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/bus"
	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/label"
	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/state"
)

const usage = `usage: labelctl [--dir DIR] [--lock-timeout D] <command> [flags]
commands:
  register    --id ID --kind KIND [--parent P] [--session S] [--pid N|ppid] [--host H] [--cwd D]
              [--track N] [--branch B] [--alias A] [--model M] [--effort E]
              [--follow-active true|false] [--source S] [--state ST] [--derive [--config-dir D]]
  update      --id ID [same field flags; only given flags are changed] [--clear k1,k2]
  heartbeat   --id ID [--state ST]
  unregister  --id ID
  reap        --id ID
  switch-alias --alias A [--model M] [--effort E]
  get         --id ID [--json]
  list        [--json|--text] [--kind K]
  snapshot
  watch       [--since N|now] [--interval-ms 100] [--text] [--socket]
  verify
  repair      (re-fold base.json+events.jsonl and rewrite fold.json/snapshot.json)
  label       ID
ids: ^[A-Za-z0-9._:@/-]{1,160}$ (others: exit 1). --lock-timeout / LABEL_SYNC_LOCK_TIMEOUT
bounds the writer-lock wait (default 2s; timeout = exit 2).
exit: 0 ok, 1 finding/invalid, 2 cannot determine (never a pass)`

// cleanWriter strips terminal-control, bidi and invalid bytes from
// everything labelctl prints (review finding 2): no input can drive the
// operator's terminal through labelctl output, under any locale.
type cleanWriter struct{ w io.Writer }

func (c cleanWriter) Write(p []byte) (int, error) {
	if _, err := io.WriteString(c.w, label.CleanText(string(p))); err != nil { // MUT:cleanout
		return 0, err
	}
	return len(p), nil
}

// rcFor maps a store error to an exit code: a busy lock is "cannot
// determine" (2), everything else a finding (1).
func rcFor(err error) int {
	if errors.Is(err, state.ErrLockTimeout) {
		return 2
	}
	return 1
}

func badID(errw io.Writer, id string) int {
	fmt.Fprintf(errw, "labelctl: invalid id %q (want ^[A-Za-z0-9._:@/-]{1,160}$)\n", id)
	return 1
}

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

func run(args []string, out, errw io.Writer) int {
	out, errw = cleanWriter{out}, cleanWriter{errw}
	opts := state.OptionsFromEnv()
	for len(args) > 0 {
		name, val, hasVal := strings.Cut(args[0], "=")
		if name != "--dir" && name != "--lock-timeout" {
			break
		}
		if !hasVal {
			if len(args) < 2 {
				fmt.Fprintln(errw, usage)
				return 2
			}
			val, args = args[1], args[2:]
		} else {
			args = args[1:]
		}
		if name == "--dir" {
			opts.Dir = val
		} else if d, ok := state.ParseDuration(val); ok && d > 0 {
			opts.LockTimeout = d
		} else {
			fmt.Fprintf(errw, "labelctl: bad --lock-timeout %q\n", val)
			return 2
		}
	}
	if len(args) == 0 {
		fmt.Fprintln(errw, usage)
		return 2
	}
	st, err := state.Open(opts)
	if err != nil {
		fmt.Fprintf(errw, "labelctl: cannot open state dir: %v\n", err)
		return 2
	}
	cmd, rest := args[0], args[1:]
	switch cmd {
	case "register", "update":
		return cmdWrite(st, cmd, rest, out, errw)
	case "heartbeat":
		fs, id, stateFlag := idFlags("heartbeat", errw)
		if rc := parse(fs, rest); rc >= 0 {
			return rc
		}
		patch := map[string]string{}
		if *stateFlag != "" {
			patch["state"] = *stateFlag
		}
		return apply(st, model.Event{Type: model.EvHeartbeat, ID: *id, Patch: patch}, out, errw)
	case "unregister", "reap":
		fs, id, _ := idFlags(cmd, errw)
		if rc := parse(fs, rest); rc >= 0 {
			return rc
		}
		t := model.EvUnregister
		if cmd == "reap" {
			t = model.EvReap
		}
		return apply(st, model.Event{Type: t, ID: *id}, out, errw)
	case "switch-alias":
		fs := flag.NewFlagSet(cmd, flag.ContinueOnError)
		fs.SetOutput(errw)
		al := fs.String("alias", "", "alias (claude1, claude2, ...)")
		mo := fs.String("model", "", "model")
		ef := fs.String("effort", "", "effort")
		if rc := parse(fs, rest); rc >= 0 {
			return rc
		}
		ev, err := st.Apply(model.Event{Type: model.EvAliasSwitch, Active: &model.Active{Alias: *al, Model: *mo, Effort: *ef}})
		if err != nil {
			fmt.Fprintf(errw, "labelctl: %v\n", err)
			return rcFor(err)
		}
		fmt.Fprintf(out, "active alias=%s model=%s effort=%s seq=%d\n", orQ(ev.Active.Alias), orQ(ev.Active.Model), orQ(ev.Active.Effort), ev.Seq)
		return 0
	case "get", "label":
		var id string
		asJSON := false
		if cmd == "label" {
			if len(rest) != 1 {
				fmt.Fprintln(errw, usage)
				return 2
			}
			id = rest[0]
		} else {
			fs := flag.NewFlagSet(cmd, flag.ContinueOnError)
			fs.SetOutput(errw)
			idf := fs.String("id", "", "entity id")
			js := fs.Bool("json", false, "json output")
			if rc := parse(fs, rest); rc >= 0 {
				return rc
			}
			id, asJSON = *idf, *js
		}
		if !label.ValidID(id) {
			return badID(errw, id)
		}
		snap, err := st.Snapshot()
		if err != nil {
			fmt.Fprintf(errw, "labelctl: %v\n", err)
			return 2
		}
		for _, e := range snap.Entities {
			if e.ID == id {
				if asJSON {
					b, _ := json.Marshal(e)
					fmt.Fprintln(out, string(b))
				} else {
					fmt.Fprintln(out, textLine(e, false))
				}
				return 0
			}
		}
		fmt.Fprintf(errw, "labelctl: unknown id %q\n", id)
		return 1
	case "list", "snapshot":
		fs := flag.NewFlagSet(cmd, flag.ContinueOnError)
		fs.SetOutput(errw)
		js := fs.Bool("json", false, "json output")
		_ = fs.Bool("text", false, "text output (default)")
		kind := fs.String("kind", "", "filter by kind")
		if rc := parse(fs, rest); rc >= 0 {
			return rc
		}
		snap, err := st.Snapshot()
		if err != nil {
			fmt.Fprintf(errw, "labelctl: %v\n", err)
			return 2
		}
		if *kind != "" {
			keep := snap.Entities[:0:0]
			for _, e := range snap.Entities {
				if e.Kind == *kind {
					keep = append(keep, e)
				}
			}
			snap.Entities = keep
		}
		if *js || cmd == "snapshot" {
			b, _ := json.MarshalIndent(snap, "", " ")
			fmt.Fprintln(out, string(b))
			return 0
		}
		for _, e := range snap.Entities {
			fmt.Fprintln(out, textLine(e, true))
		}
		return 0
	case "watch":
		return cmdWatch(st, rest, out, errw)
	case "verify":
		if err := st.Verify(); err != nil {
			fmt.Fprintf(errw, "labelctl verify: PROBLEM: %v\n", err)
			return 1
		}
		seq, err := st.Seq()
		if err != nil {
			fmt.Fprintf(errw, "labelctl verify: cannot determine: %v\n", err)
			return 2
		}
		fmt.Fprintf(out, "labelctl verify: OK seq=%d dir=%s\n", seq, st.Dir())
		return 0
	case "repair":
		n, err := st.Repair()
		if err != nil {
			fmt.Fprintf(errw, "labelctl repair: cannot determine: %v\n", err)
			return 2
		}
		if err := st.Verify(); err != nil {
			fmt.Fprintf(errw, "labelctl repair: PROBLEM after re-fold: %v\n", err)
			return 1
		}
		fmt.Fprintf(out, "labelctl repair: repaired from base.json+events.jsonl; %d local entit(y/ies) with a pid and no recorded PID namespace (bounded unknown-namespace sweep applies)\n", n)
		return 0
	case "-h", "--help", "help":
		fmt.Fprintln(out, usage)
		return 0
	}
	fmt.Fprintf(errw, "labelctl: unknown command %q\n%s\n", cmd, usage)
	return 2
}

func orQ(s string) string {
	if s == "" {
		return "?"
	}
	return s
}

func textLine(e model.Entity, long bool) string {
	if !long {
		if e.Stale {
			return e.Label + " [stale]"
		}
		return e.Label
	}
	st := e.State
	if e.Stale {
		st += "(stale)"
	}
	return fmt.Sprintf("%-8s %-24s %-9s %s", e.Kind, e.ID, st, e.Label)
}

func idFlags(name string, errw io.Writer) (*flag.FlagSet, *string, *string) {
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	fs.SetOutput(errw)
	id := fs.String("id", "", "entity id")
	stt := fs.String("state", "", "state")
	return fs, id, stt
}

// parse returns -1 on success, otherwise the exit code to use.
func parse(fs *flag.FlagSet, args []string) int {
	if err := fs.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return 0
		}
		return 2
	}
	return -1
}

func apply(st *state.Store, ev model.Event, out, errw io.Writer) int {
	if ev.ID == "" {
		fmt.Fprintln(errw, "labelctl: --id required")
		return 2
	}
	if !label.ValidID(ev.ID) {
		return badID(errw, ev.ID)
	}
	got, err := st.Apply(ev)
	if err != nil {
		fmt.Fprintf(errw, "labelctl: %v\n", err)
		return rcFor(err)
	}
	fmt.Fprintf(out, "ok seq=%d\n", got.Seq)
	return 0
}

type fieldFlags struct {
	id, kind, parent, session, host, cwd, track, branch, alias, model, effort, source, stateF, follow, pid, cfgDir, clear *string
	derive                                                                                                                *bool
}

func newFieldFlags(fs *flag.FlagSet) *fieldFlags {
	f := &fieldFlags{}
	f.id = fs.String("id", "", "entity id")
	f.kind = fs.String("kind", "", "session|agent|subagent|stream|shell|command|flow")
	f.parent = fs.String("parent", "", "parent entity id")
	f.session = fs.String("session", "", "session id")
	f.host = fs.String("host", "", "host (default: this host)")
	f.cwd = fs.String("cwd", "", "working directory")
	f.track = fs.String("track", "", "track number")
	f.branch = fs.String("branch", "", "branch")
	f.alias = fs.String("alias", "", "alias")
	f.model = fs.String("model", "", "model")
	f.effort = fs.String("effort", "", "effort")
	f.source = fs.String("source", "", "who reported this entity")
	f.stateF = fs.String("state", "", "running|idle|done|unknown")
	f.follow = fs.String("follow-active", "", "true|false (register default: true)")
	f.pid = fs.String("pid", "", "process id, or 'ppid' for the caller's parent")
	f.cfgDir = fs.String("config-dir", "", "CLAUDE_CONFIG_DIR to derive for (with --derive)")
	f.derive = fs.Bool("derive", false, "fill unset fields via the canonical track_branch_label.sh")
	f.clear = fs.String("clear", "", "update: comma-separated fields to CLEAR (parent session pid host cwd track branch alias model effort source)")
	return f
}

func labeler() string {
	if p := os.Getenv("LABEL_SYNC_LABELER"); p != "" {
		return p
	}
	if exe, err := os.Executable(); err == nil {
		// <constitution>/scripts/label-sync/... : search upwards for the script
		for d := filepath.Dir(exe); d != "/" && d != "."; d = filepath.Dir(d) {
			c := filepath.Join(d, "scripts", "multitrack", "track_branch_label.sh")
			if _, err := os.Stat(c); err == nil {
				return c
			}
			c = filepath.Join(d, "multitrack", "track_branch_label.sh")
			if _, err := os.Stat(c); err == nil {
				return c
			}
		}
	}
	return ""
}

func unq(s string) string {
	if s == "?" {
		return ""
	}
	return s
}

func cmdWrite(st *state.Store, cmd string, args []string, out, errw io.Writer) int {
	fs := flag.NewFlagSet(cmd, flag.ContinueOnError)
	fs.SetOutput(errw)
	f := newFieldFlags(fs)
	if rc := parse(fs, args); rc >= 0 {
		return rc
	}
	set := map[string]bool{}
	fs.Visit(func(x *flag.Flag) { set[x.Name] = true })
	if *f.id == "" {
		fmt.Fprintln(errw, "labelctl: --id required")
		return 2
	}
	if !label.ValidID(*f.id) {
		return badID(errw, *f.id)
	}
	for _, v := range []string{*f.parent, *f.session} {
		if v != "" && !label.ValidID(v) {
			return badID(errw, v)
		}
	}
	pidStr := *f.pid
	if pidStr == "ppid" {
		pidStr = strconv.Itoa(os.Getppid())
	}
	vals := map[string]string{"parent_id": *f.parent, "session_id": *f.session, "host": *f.host, "cwd": *f.cwd,
		"track": *f.track, "branch": *f.branch, "alias": *f.alias, "model": *f.model, "effort": *f.effort,
		"source": *f.source, "state": *f.stateF, "follow_active": *f.follow, "pid": pidStr}
	flagOf := map[string]string{"parent_id": "parent", "session_id": "session", "follow_active": "follow-active"}
	derivedAlias := false
	if *f.derive {
		script := labeler()
		if script == "" {
			fmt.Fprintln(errw, "labelctl: --derive: canonical labeler track_branch_label.sh not found (set LABEL_SYNC_LABELER)")
			return 2
		}
		cwd := *f.cwd
		if cwd == "" {
			cwd, _ = os.Getwd()
		}
		env := os.Environ()
		if *f.cfgDir != "" {
			env = append(env, "CLAUDE_CONFIG_DIR="+*f.cfgDir)
		}
		d, err := label.Derive(script, cwd, env)
		if err != nil {
			fmt.Fprintf(errw, "labelctl: --derive failed: %v\n", err)
			return 2
		}
		derivedAlias = !set["alias"] && unq(d.Alias) != ""
		for k, v := range map[string]string{"track": unq(d.Track), "branch": unq(d.Branch), "alias": unq(d.Alias), "model": unq(d.Model), "effort": unq(d.Effort)} {
			if !set[k] && v != "" {
				vals[k] = v
				set[k] = true
			}
		}
	}
	isSet := func(k string) bool {
		n := k
		if x, ok := flagOf[k]; ok {
			n = x
		}
		if k == "pid" && *f.pid != "" {
			return true
		}
		return set[n] && vals[k] != ""
	}
	var ev model.Event
	if cmd == "register" {
		if !model.ValidKind(*f.kind) {
			fmt.Fprintf(errw, "labelctl: --kind must be one of session|agent|subagent|stream|shell|command|flow (got %q)\n", *f.kind)
			return 1
		}
		e := model.Entity{ID: *f.id, Kind: *f.kind, ParentID: vals["parent_id"], SessionID: vals["session_id"],
			Host: vals["host"], Cwd: vals["cwd"], Track: vals["track"], Branch: vals["branch"], Alias: vals["alias"],
			Model: vals["model"], Effort: vals["effort"], Source: vals["source"], State: vals["state"], FollowActive: true}
		if e.Host == "" {
			e.Host, _ = os.Hostname()
		}
		if e.Cwd == "" {
			e.Cwd, _ = os.Getwd()
		}
		if pidStr != "" {
			n, err := strconv.Atoi(pidStr)
			if err != nil {
				fmt.Fprintf(errw, "labelctl: invalid --pid %q\n", pidStr)
				return 1
			}
			e.PID = n
		}
		if vals["follow_active"] != "" {
			b, err := strconv.ParseBool(vals["follow_active"])
			if err != nil {
				fmt.Fprintf(errw, "labelctl: invalid --follow-active %q\n", vals["follow_active"])
				return 1
			}
			e.FollowActive = b
		} else if derivedAlias {
			// Process-bound truth (CONTRACT §4.2): an alias DERIVED from this
			// process's CLAUDE_CONFIG_DIR pins the entity, so two terminals on
			// two aliases each keep their own. No read of the active alias is
			// needed, so there is no TOCTOU window.
			e.FollowActive = false // MUT:derivepin
		} else if e.Alias != "" {
			// An EXPLICIT --alias pins too (review-2 finding 4): only alias-less
			// roots follow the active context (CONTRACT §4.2).
			e.FollowActive = false // MUT:explicitpin
		}
		if pidStr != "" && (e.PID < 0 || e.PID > state.MaxPID) {
			fmt.Fprintf(errw, "labelctl: invalid --pid %q (want 0..%d)\n", pidStr, state.MaxPID)
			return 1
		}
		ev = model.Event{Type: model.EvRegister, Entity: &e}
	} else {
		patch := map[string]string{}
		for k := range vals {
			if isSet(k) {
				patch[k] = vals[k]
			}
		}
		if *f.clear != "" {
			clearable := map[string]string{"parent": "parent_id", "session": "session_id", "pid": "pid", "host": "host",
				"cwd": "cwd", "track": "track", "branch": "branch", "alias": "alias", "model": "model", "effort": "effort", "source": "source"}
			for _, k := range strings.Split(*f.clear, ",") {
				key, ok := clearable[strings.TrimSpace(k)]
				if !ok {
					fmt.Fprintf(errw, "labelctl update: field %q cannot be cleared\n", k)
					return 1
				}
				if _, dup := patch[key]; dup {
					fmt.Fprintf(errw, "labelctl update: %q both set and cleared\n", k)
					return 1
				}
				patch[key] = "" // MUT:clear
			}
		}
		if a, ok := patch["alias"]; ok && a != "" && !set["follow-active"] {
			patch["follow_active"] = "false" // explicit alias pins (CONTRACT §4.3) // MUT:updatepin
		}
		if v, ok := patch["pid"]; ok && v != "" {
			if n, err := strconv.Atoi(v); err != nil || n < 0 || n > state.MaxPID {
				fmt.Fprintf(errw, "labelctl: invalid --pid %q (want 0..%d)\n", v, state.MaxPID)
				return 1
			}
		}
		if len(patch) == 0 {
			fmt.Fprintln(errw, "labelctl update: no fields to change")
			return 2
		}
		ev = model.Event{Type: model.EvUpdate, ID: *f.id, Patch: patch}
	}
	got, err := st.Apply(ev)
	if err != nil {
		fmt.Fprintf(errw, "labelctl: %v\n", err)
		return rcFor(err)
	}
	snap, err := st.Snapshot()
	if err != nil {
		fmt.Fprintf(errw, "labelctl: applied seq=%d but cannot render: %v\n", got.Seq, err)
		return 2
	}
	for _, e := range snap.Entities {
		if e.ID == *f.id {
			fmt.Fprintln(out, e.Label)
			return 0
		}
	}
	return 0
}

func cmdWatch(st *state.Store, args []string, out, errw io.Writer) int {
	fs := flag.NewFlagSet("watch", flag.ContinueOnError)
	fs.SetOutput(errw)
	since := fs.String("since", "now", "sequence to start after, or 'now'")
	ms := fs.Int("interval-ms", 100, "poll interval")
	text := fs.Bool("text", false, "print labels instead of event JSON")
	useSock := fs.Bool("socket", false, "subscribe via label-busd socket")
	max := fs.Int("max", 0, "exit after N events (0 = unlimited)")
	if rc := parse(fs, args); rc >= 0 {
		return rc
	}
	var from uint64 = bus.FromNow
	if *since != "now" {
		n, err := strconv.ParseUint(*since, 10, 64)
		if err != nil {
			fmt.Fprintf(errw, "labelctl: bad --since %q\n", *since)
			return 2
		}
		from = n
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	var ch <-chan model.Event
	if *useSock {
		c, cl, err := bus.Dial(ctx, bus.ResolveSocket(st.Dir()), from)
		if err != nil {
			fmt.Fprintf(errw, "labelctl: socket subscribe failed (is label-busd running?): %v\n", err)
			return 2
		}
		defer cl.Close()
		ch = c
	} else {
		ch = bus.Subscribe(ctx, st, from, time.Duration(*ms)*time.Millisecond)
	}
	n := 0
	for ev := range ch {
		if *text {
			snap, err := st.Snapshot()
			if err == nil {
				for _, e := range snap.Entities {
					if ev.ID == e.ID || (ev.Entity != nil && ev.Entity.ID == e.ID) || ev.Type == model.EvAliasSwitch {
						fmt.Fprintf(out, "seq=%d %s %s %s\n", ev.Seq, ev.Type, e.ID, textLine(e, false))
					}
				}
			}
		} else {
			b, _ := json.Marshal(ev)
			fmt.Fprintln(out, string(b))
		}
		n++
		if *max > 0 && n >= *max {
			return 0
		}
	}
	return 0
}
