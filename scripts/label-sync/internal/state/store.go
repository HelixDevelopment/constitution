// Package state is the crash-safe, flock-serialised store behind label-sync:
// an append-only events.jsonl (source of truth), an internal fold.json
// (declared state), and the consumer files snapshot.json, active.json and seq.
// See docs/label-sync/CONTRACT.md.
package state

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
)

// Options configure a Store. Zero values get production defaults.
type Options struct {
	Dir           string
	Now           func() time.Time
	Pids          PidTable
	TTL           time.Duration // staleness TTL (default 120s)
	DoneRetention time.Duration // how long done entities stay (default 300s)
	LocalHost     string        // host name treated as "local" for pid checks
}

// DefaultDir is ${LABEL_SYNC_DIR:-$HOME/.local/state/constitution-label-sync}.
func DefaultDir() string {
	if d := os.Getenv("LABEL_SYNC_DIR"); d != "" {
		return d
	}
	h, _ := os.UserHomeDir()
	return filepath.Join(h, ".local", "state", "constitution-label-sync")
}

// Store is a handle on one state directory. Safe for concurrent use across
// goroutines and processes (flock).
type Store struct {
	opts Options
	dir  string
}

// Open creates the directory (0700) if needed and returns a Store.
func Open(o Options) (*Store, error) {
	if o.Dir == "" {
		o.Dir = DefaultDir()
	}
	if o.Now == nil {
		o.Now = func() time.Time { return time.Now().UTC() }
	}
	if o.Pids == nil {
		o.Pids = ProcPids{}
	}
	if o.TTL <= 0 {
		o.TTL = 120 * time.Second
	}
	if o.DoneRetention <= 0 {
		o.DoneRetention = 300 * time.Second
	}
	if o.LocalHost == "" {
		o.LocalHost, _ = os.Hostname()
	}
	if err := os.MkdirAll(o.Dir, 0o700); err != nil {
		return nil, err
	}
	return &Store{opts: o, dir: o.Dir}, nil
}

// Dir returns the state directory.
func (s *Store) Dir() string { return s.dir }

func (s *Store) p(name string) string { return filepath.Join(s.dir, name) }

func (s *Store) renderOpts() RenderOpts {
	return RenderOpts{Now: s.opts.Now(), Pids: s.opts.Pids, TTL: s.opts.TTL, LocalHost: s.opts.LocalHost}
}

// readEvents parses events.jsonl. A torn (unparseable) FINAL line is
// tolerated; unparseable lines elsewhere are counted in corrupt.
func (s *Store) readEvents() (evs []model.Event, corrupt int, err error) {
	f, err := os.Open(s.p("events.jsonl"))
	if errors.Is(err, os.ErrNotExist) {
		return nil, 0, nil
	}
	if err != nil {
		return nil, 0, err
	}
	defer f.Close()
	br := bufio.NewReaderSize(f, 1<<20)
	var bad []int
	n := 0
	for {
		line, rerr := br.ReadBytes('\n')
		if len(bytes.TrimSpace(line)) > 0 {
			n++
			var ev model.Event
			if json.Unmarshal(line, &ev) != nil || ev.Seq == 0 || ev.Type == "" {
				bad = append(bad, n)
			} else {
				evs = append(evs, ev)
			}
		}
		if rerr == io.EOF {
			break
		}
		if rerr != nil {
			return nil, 0, rerr
		}
	}
	for _, b := range bad {
		if b != n { // a bad FINAL line is a torn write, not corruption
			corrupt++
		}
	}
	return evs, corrupt, nil
}

// replay folds events (ignoring ones that fail to apply or are out of order).
func replay(r *Raw, evs []model.Event) {
	for _, ev := range evs {
		if ev.Seq <= r.Seq {
			continue
		}
		_ = r.Apply(ev)
		r.Seq = ev.Seq // keep seq monotone even if an event could not fold
	}
}

// load returns the declared state, caught up to the end of the event log.
// No lock needed: every file it reads is replaced atomically or append-only.
func (s *Store) load() (*Raw, error) {
	r := NewRaw()
	if b, err := os.ReadFile(s.p("fold.json")); err == nil {
		var cand Raw
		if json.Unmarshal(b, &cand) == nil && cand.Entities != nil {
			r = &cand
		}
	}
	evs, _, err := s.readEvents()
	if err != nil {
		return nil, err
	}
	if len(evs) > 0 && evs[len(evs)-1].Seq < r.Seq { // fold ahead of log: log lost; trust log
		r = NewRaw()
	}
	replay(r, evs)
	return r, nil
}

func (s *Store) persist(r *Raw) error {
	fb, err := json.Marshal(r)
	if err != nil {
		return err
	}
	if err := WriteAtomic(s.p("fold.json"), fb); err != nil {
		return err
	}
	snap := Render(r, s.renderOpts())
	sb, err := json.MarshalIndent(snap, "", " ")
	if err != nil {
		return err
	}
	if err := WriteAtomic(s.p("snapshot.json"), append(sb, '\n')); err != nil {
		return err
	}
	ab, _ := json.MarshalIndent(r.Active, "", " ")
	if err := WriteAtomic(s.p("active.json"), append(ab, '\n')); err != nil {
		return err
	}
	// seq LAST: a consumer that sees seq N can read a snapshot at >= N.
	return WriteAtomic(s.p("seq"), []byte(strconv.FormatUint(r.Seq, 10)+"\n"))
}

func (s *Store) appendEvent(ev model.Event) error {
	line, err := json.Marshal(ev)
	if err != nil {
		return err
	}
	f, err := os.OpenFile(s.p("events.jsonl"), os.O_CREATE|os.O_RDWR|os.O_APPEND, 0o600)
	if err != nil {
		return err
	}
	defer f.Close()
	// heal a torn final line: a fragment that is not a complete event is
	// truncated away (it was never acknowledged); a complete one just gets
	// its missing newline.
	if st, err := f.Stat(); err == nil && st.Size() > 0 {
		all, rerr := os.ReadFile(s.p("events.jsonl"))
		if rerr != nil {
			return rerr
		}
		if all[len(all)-1] != '\n' {
			cut := bytes.LastIndexByte(all, '\n') + 1
			var probe model.Event
			if json.Unmarshal(all[cut:], &probe) == nil && probe.Seq != 0 {
				line = append([]byte{'\n'}, line...)
			} else if err := f.Truncate(int64(cut)); err != nil {
				return err
			}
		}
	}
	if _, err := f.Write(append(line, '\n')); err != nil {
		return err
	}
	return f.Sync()
}

// Apply validates, sequences, logs and folds one event; it assigns Seq and
// TS. A rejected event is not logged.
func (s *Store) Apply(ev model.Event) (model.Event, error) {
	lk, err := acquire(s.p("lock"))
	if err != nil {
		return ev, err
	}
	defer lk.release()
	return s.applyLocked(ev)
}

func (s *Store) applyLocked(ev model.Event) (model.Event, error) {
	r, err := s.load()
	if err != nil {
		return ev, err
	}
	ev.Seq = r.Seq + 1
	ev.TS = s.opts.Now()
	if ev.Type == model.EvRegister && ev.Entity != nil {
		ev.Entity.UpdatedAt = ev.TS
	}
	if err := r.Apply(ev); err != nil {
		return ev, err
	}
	if err := s.appendEvent(ev); err != nil {
		return ev, err
	}
	return ev, s.persist(r)
}

// Snapshot returns the rendered view as of now (staleness included),
// computed from the log-complete declared state.
func (s *Store) Snapshot() (*model.Snapshot, error) {
	r, err := s.load()
	if err != nil {
		return nil, err
	}
	snap := Render(r, s.renderOpts())
	return &snap, nil
}

// Seq returns the highest event sequence in the log.
func (s *Store) Seq() (uint64, error) {
	r, err := s.load()
	if err != nil {
		return 0, err
	}
	return r.Seq, nil
}

// EventsSince returns events with Seq > seq, in order.
func (s *Store) EventsSince(seq uint64) ([]model.Event, error) {
	evs, _, err := s.readEvents()
	if err != nil {
		return nil, err
	}
	out := evs[:0:0]
	for _, ev := range evs {
		if ev.Seq > seq {
			out = append(out, ev)
		}
	}
	return out, nil
}

// Reconcile is the level-triggered convergence step (§11.4.233): reap done
// entities past retention, then, if the rendered view differs from the
// published snapshot.json (e.g. an entity just went stale), bump seq and
// republish. Idempotent: running it twice in a row changes nothing.
func (s *Store) Reconcile() (changed bool, reaped []string, err error) {
	lk, err := acquire(s.p("lock"))
	if err != nil {
		return false, nil, err
	}
	defer lk.release()
	r, err := s.load()
	if err != nil {
		return false, nil, err
	}
	now := s.opts.Now()
	for id, e := range r.Entities {
		if e.State == model.StateDone && now.Sub(e.UpdatedAt) > s.opts.DoneRetention {
			if _, err := s.applyLocked(model.Event{Type: model.EvReap, ID: id}); err != nil {
				return changed, reaped, err
			}
			reaped = append(reaped, id)
			changed = true
		}
	}
	if len(reaped) > 0 {
		if r, err = s.load(); err != nil {
			return changed, reaped, err
		}
	}
	want := Render(r, s.renderOpts())
	var have model.Snapshot
	if b, rerr := os.ReadFile(s.p("snapshot.json")); rerr != nil || json.Unmarshal(b, &have) != nil ||
		!reflect.DeepEqual(normalise(have), normalise(want)) {
		if _, err := s.applyLocked(model.Event{Type: model.EvReconcile}); err != nil {
			return changed, reaped, err
		}
		changed = true
	}
	return changed, reaped, nil
}

// normalise drops the fields that legitimately differ between renders of the
// same logical state, via a JSON round trip so time zones/monotonic clocks
// cannot cause false differences.
func normalise(s model.Snapshot) any {
	s.Seq = 0
	s.GeneratedAt = time.Time{}
	b, _ := json.Marshal(s)
	var v any
	_ = json.Unmarshal(b, &v)
	return v
}

// Verify checks the on-disk files for consistency: log parseable (a torn
// final line is fine), fold.json equals a from-scratch replay, snapshot.json
// parses and is not ahead of the log, seq file matches.
func (s *Store) Verify() error {
	var probs []string
	evs, corrupt, err := s.readEvents()
	if err != nil {
		return err
	}
	if corrupt > 0 {
		probs = append(probs, fmt.Sprintf("events.jsonl: %d corrupt non-final line(s)", corrupt))
	}
	var last uint64
	for _, ev := range evs {
		if ev.Seq <= last {
			probs = append(probs, fmt.Sprintf("events.jsonl: non-monotonic seq %d after %d", ev.Seq, last))
		}
		last = ev.Seq
	}
	want := NewRaw()
	replay(want, evs)
	if b, err := os.ReadFile(s.p("fold.json")); err != nil {
		if len(evs) > 0 {
			probs = append(probs, "fold.json missing")
		}
	} else {
		var got Raw
		if json.Unmarshal(b, &got) != nil {
			probs = append(probs, "fold.json unparseable")
		} else if got.Seq == want.Seq && !reflect.DeepEqual(canon(&got), canon(want)) {
			probs = append(probs, "fold.json differs from replay of events.jsonl")
		}
	}
	if b, err := os.ReadFile(s.p("snapshot.json")); err != nil {
		if len(evs) > 0 {
			probs = append(probs, "snapshot.json missing")
		}
	} else {
		var sn model.Snapshot
		if json.Unmarshal(b, &sn) != nil {
			probs = append(probs, "snapshot.json unparseable (torn/truncated)")
		} else if sn.Seq > last {
			probs = append(probs, "snapshot.json is ahead of the event log")
		}
	}
	if b, err := os.ReadFile(s.p("seq")); err == nil {
		n, perr := strconv.ParseUint(strings.TrimSpace(string(b)), 10, 64)
		if perr != nil {
			probs = append(probs, "seq file unparseable")
		} else if n > last {
			probs = append(probs, "seq file is ahead of the event log")
		}
	}
	if len(probs) > 0 {
		return errors.New(strings.Join(probs, "; "))
	}
	return nil
}

func canon(r *Raw) any {
	b, _ := json.Marshal(r)
	var v any
	_ = json.Unmarshal(b, &v)
	return v
}

// PeekSeq reads only the tiny seq file (cheap; used by pollers). Returns 0
// when absent/unparseable.
func (s *Store) PeekSeq() uint64 {
	b, err := os.ReadFile(s.p("seq"))
	if err != nil {
		return 0
	}
	n, _ := strconv.ParseUint(strings.TrimSpace(string(b)), 10, 64)
	return n
}

// OptionsFromEnv builds Options from LABEL_SYNC_DIR, LABEL_SYNC_TTL and
// LABEL_SYNC_DONE_RETENTION (Go durations like "90s", or bare seconds).
func OptionsFromEnv() Options {
	o := Options{Dir: os.Getenv("LABEL_SYNC_DIR")}
	o.TTL = envDur("LABEL_SYNC_TTL")
	o.DoneRetention = envDur("LABEL_SYNC_DONE_RETENTION")
	return o
}

func envDur(k string) time.Duration {
	v := os.Getenv(k)
	if v == "" {
		return 0
	}
	if d, err := time.ParseDuration(v); err == nil {
		return d
	}
	if n, err := strconv.Atoi(v); err == nil {
		return time.Duration(n) * time.Second
	}
	return 0
}
