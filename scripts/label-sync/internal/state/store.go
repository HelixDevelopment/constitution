// Package state is the crash-safe, flock-serialised store behind label-sync:
// an append-only events.jsonl (source of truth, compacted onto base.json), an
// internal fold.json (declared state + log offset index), and the consumer
// files snapshot.json, active.json and seq. See docs/label-sync/CONTRACT.md.
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
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/label"
	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
)

// Compaction / lock defaults (CONTRACT §1.2). All overridable via Options and
// the LABEL_SYNC_* environment (OptionsFromEnv).
const (
	DefaultCompactEvents = 5000
	DefaultCompactBytes  = 2 << 20
	DefaultKeepTail      = 256
	DefaultLockTimeout   = 2 * time.Second
	maxCwdRunes          = 4096
	maxHostRunes         = 255
	orphanTmpAge         = time.Minute
	// DefaultSweepAfter: an entity whose LOCAL process is provably gone is
	// removed once it has not been updated for this long (CONTRACT §1.3).
	DefaultSweepAfter = 15 * time.Minute
	// DefaultSweepBatch bounds the entities one transaction sweeps.
	DefaultSweepBatch = 256
	// MaxPID is the largest pid accepted (Linux PID_MAX_LIMIT, 2^22).
	MaxPID = 1 << 22
)

// Options configure a Store. Zero values get production defaults.
type Options struct {
	Dir           string
	Now           func() time.Time
	Pids          PidTable
	TTL           time.Duration // staleness TTL (default 120s)
	DoneRetention time.Duration // how long done entities stay (default 300s)
	LocalHost     string        // host name treated as "local" for pid checks
	LockTimeout   time.Duration // bound on acquiring the writer lock (default 2s)
	CompactEvents int           // compact when the log holds more events (default 5000)
	CompactBytes  int64         // ... or more bytes (default 2 MiB)
	KeepTail      int           // events kept in the log after compaction (default 256)
	SweepAfter    time.Duration // stale-sweep age (default 15m; < 0 disables)
	SweepBatch    int           // max entities swept per transaction (default 256)
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
	// hook, when set (tests only), is called after each durable step of a
	// write transaction; a non-nil return aborts the transaction right there,
	// which is exactly the on-disk state a kill -9 at that point leaves.
	hook func(point string) error
}

// currentUID is a seam for the ownership check (tests fake another owner).
var currentUID = os.Getuid

// Open creates the directory (0700) if needed, enforces 0700 on an existing
// one, refuses a directory owned by another uid, removes orphaned temp files
// older than a minute, and returns a Store.
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
	if o.LockTimeout <= 0 {
		o.LockTimeout = DefaultLockTimeout
	}
	if o.CompactEvents <= 0 {
		o.CompactEvents = DefaultCompactEvents
	}
	if o.CompactBytes <= 0 {
		o.CompactBytes = DefaultCompactBytes
	}
	if o.KeepTail <= 0 {
		o.KeepTail = DefaultKeepTail
	}
	if o.SweepAfter == 0 {
		o.SweepAfter = DefaultSweepAfter
	}
	if o.SweepBatch <= 0 {
		o.SweepBatch = DefaultSweepBatch
	}
	if o.KeepTail > o.CompactEvents {
		o.KeepTail = o.CompactEvents
	}
	if err := os.MkdirAll(o.Dir, 0o700); err != nil {
		return nil, err
	}
	fi, err := os.Stat(o.Dir)
	if err != nil {
		return nil, err
	}
	if !fi.IsDir() {
		return nil, fmt.Errorf("state dir %s is not a directory", o.Dir)
	}
	if st, ok := fi.Sys().(*syscall.Stat_t); ok && int(st.Uid) != currentUID() { // MUT:owner
		return nil, fmt.Errorf("state dir %s is owned by uid %d, not %d — refusing", o.Dir, st.Uid, currentUID())
	}
	if fi.Mode().Perm() != 0o700 {
		if err := os.Chmod(o.Dir, 0o700); err != nil {
			return nil, err
		}
	}
	s := &Store{opts: o, dir: o.Dir}
	s.cleanOrphans() // MUT:orphans
	return s, nil
}

// cleanOrphans removes ".*.tmp-*" files left by a killed writer. Only files
// older than orphanTmpAge are touched, so a concurrent in-flight write (ms)
// is never disturbed.
func (s *Store) cleanOrphans() {
	m, _ := filepath.Glob(filepath.Join(s.dir, ".*.tmp-*"))
	for _, p := range m {
		if fi, err := os.Lstat(p); err == nil && fi.Mode().IsRegular() && s.opts.Now().Sub(fi.ModTime()) > orphanTmpAge {
			_ = os.Remove(p)
		}
	}
}

// Dir returns the state directory.
func (s *Store) Dir() string { return s.dir }

func (s *Store) p(name string) string { return filepath.Join(s.dir, name) }

func (s *Store) step(point string) error {
	if s.hook != nil {
		return s.hook(point)
	}
	return nil
}

func (s *Store) renderOpts() RenderOpts {
	return RenderOpts{Now: s.opts.Now(), Pids: s.opts.Pids, TTL: s.opts.TTL, LocalHost: s.opts.LocalHost}
}

// ---------------------------------------------------------------- log scan

type scanResult struct {
	evs     []model.Event
	end     int64 // offset just past the last complete line (excludes a torn tail)
	corrupt int   // unparseable NON-final lines
}

func parseEvent(line []byte) (model.Event, bool) {
	var ev model.Event
	if json.Unmarshal(line, &ev) != nil || ev.Seq == 0 || ev.Type == "" {
		return ev, false
	}
	return ev, true
}

// scanLog parses events.jsonl from byte offset from. A torn (unparseable)
// FINAL line is tolerated and excluded from end; unparseable lines elsewhere
// are counted in corrupt.
func scanLog(f *os.File, from int64) (scanResult, error) {
	res := scanResult{end: from}
	if _, err := f.Seek(from, io.SeekStart); err != nil {
		return res, err
	}
	br := bufio.NewReaderSize(f, 1<<16)
	pos := from
	badPending := false
	for {
		line, rerr := br.ReadBytes('\n')
		if len(line) > 0 {
			pos += int64(len(line))
			if t := bytes.TrimSpace(line); len(t) > 0 {
				if badPending { // the previous bad line was not final
					res.corrupt++
					badPending = false
				}
				if ev, ok := parseEvent(t); ok {
					res.evs = append(res.evs, ev)
					res.end = pos
				} else {
					badPending = true
				}
			} else if !badPending {
				res.end = pos
			}
		}
		if rerr == io.EOF {
			break
		}
		if rerr != nil {
			return res, rerr
		}
	}
	return res, nil // MUT:torn
}

func inode(fi os.FileInfo) uint64 {
	if st, ok := fi.Sys().(*syscall.Stat_t); ok {
		return st.Ino
	}
	return 0
}

// ------------------------------------------------------------- load / fold

func (s *Store) readJSONRaw(name string) (*Raw, error) {
	b, err := os.ReadFile(s.p(name))
	if errors.Is(err, os.ErrNotExist) {
		return nil, os.ErrNotExist
	}
	if err != nil {
		return nil, err
	}
	var r Raw
	if err := json.Unmarshal(b, &r); err != nil || r.Entities == nil {
		return nil, fmt.Errorf("%s unparseable", name)
	}
	return &r, nil
}

// readBase returns the authoritative compaction base (empty at seq 0 when
// no compaction has happened yet).
func (s *Store) readBase() (*Raw, error) {
	r, err := s.readJSONRaw("base.json")
	if errors.Is(err, os.ErrNotExist) {
		return NewRaw(), nil
	}
	if err != nil {
		return nil, err
	}
	r.Index = logIndex{}
	return r, nil
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

// loadOnce is one attempt at the declared state, caught up to the end of the
// log. FAST PATH: fold.json plus only the events after its recorded offset.
// FULL PATH: base.json plus the whole (bounded) log. retry=true reports a
// read that raced a compaction (log newer than base) and must be repeated.
func (s *Store) loadOnce() (r *Raw, retry bool, err error) {
	f, ferr := os.Open(s.p("events.jsonl"))
	if ferr != nil && !errors.Is(ferr, os.ErrNotExist) {
		return nil, false, ferr
	}
	var ino uint64
	var size int64
	if f != nil {
		defer f.Close()
		fi, err := f.Stat()
		if err != nil {
			return nil, false, err
		}
		ino, size = inode(fi), fi.Size()
	}
	if fold, _ := s.readJSONRaw("fold.json"); fold != nil && f != nil && fold.Index.Ino == ino && ino != 0 && fold.Index.Off <= size {
		res, err := scanLog(f, fold.Index.Off)
		if err == nil && (len(res.evs) == 0 || res.evs[0].Seq == fold.Seq+1) {
			replay(fold, res.evs)
			fold.Index.Events += len(res.evs)
			fold.Index.Off = res.end
			return fold, false, nil
		}
	}
	base, err := s.readBase()
	if err != nil {
		return nil, false, err
	}
	r = base
	if f == nil {
		return r, false, nil
	}
	res, err := scanLog(f, 0)
	if err != nil {
		return nil, false, err
	}
	var tail []model.Event
	for _, ev := range res.evs {
		if ev.Seq > base.Seq {
			tail = append(tail, ev)
		}
	}
	if len(tail) > 0 && tail[0].Seq > base.Seq+1 {
		retry = true // log rotated after we read base.json: read again
	}
	replay(r, tail)
	r.Index = logIndex{Ino: ino, Off: res.end, Events: len(res.evs), BaseSeq: base.Seq}
	return r, retry, nil
}

// load returns the declared state. No lock needed: every file it reads is
// replaced atomically or append-only; a read that races a compaction is
// retried.
func (s *Store) load() (*Raw, error) {
	var r *Raw
	for attempt := 0; attempt < 8; attempt++ {
		var retry bool
		var err error
		if r, retry, err = s.loadOnce(); err != nil {
			return nil, err
		}
		if !retry {
			return r, nil
		}
	}
	return r, nil // persistent gap: best effort; Verify reports it
}

// ------------------------------------------------------------------ writes

func (s *Store) persist(r *Raw) error {
	fb, err := json.Marshal(r)
	if err != nil {
		return err
	}
	if err := WriteAtomic(s.p("fold.json"), fb); err != nil { // MUT:foldfirst
		return err
	}
	if err := s.step("persist:fold"); err != nil {
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
	if err := s.step("persist:snapshot"); err != nil {
		return err
	}
	ab, _ := json.MarshalIndent(r.Active, "", " ")
	if err := WriteAtomic(s.p("active.json"), append(ab, '\n')); err != nil {
		return err
	}
	if err := s.step("persist:active"); err != nil {
		return err
	}
	// seq LAST: a consumer that sees seq N can read a snapshot at >= N.
	if err := WriteAtomic(s.p("seq"), []byte(strconv.FormatUint(r.Seq, 10)+"\n")); err != nil { // MUT:seqlast
		return err
	}
	return s.step("persist:seq")
}

// lastLineStart returns the offset just past the last '\n' before size (0 if
// none), reading backwards in small chunks — never the whole file.
func lastLineStart(f *os.File, size int64) (int64, error) {
	buf := make([]byte, 4096)
	for end := size; end > 0; {
		n := int64(len(buf))
		if n > end {
			n = end
		}
		if _, err := f.ReadAt(buf[:n], end-n); err != nil && err != io.EOF {
			return 0, err
		}
		if i := bytes.LastIndexByte(buf[:n], '\n'); i >= 0 {
			return end - n + int64(i) + 1, nil
		}
		end -= n
	}
	return 0, nil
}

// appendEvent durably appends one event and advances r.Index. The last byte
// is checked with ReadAt (O(1)); a torn final fragment that is not a complete
// event is truncated away (it was never acknowledged), a complete one just
// gets its missing newline.
func (s *Store) appendEvent(r *Raw, ev model.Event) error { return s.appendEvents(r, []model.Event{ev}) }

// appendEvents appends several events with ONE write and ONE fsync (the stale
// sweeper reaps up to SweepBatch entities per transaction: one fsync each
// would hold the writer lock for seconds).
func (s *Store) appendEvents(r *Raw, evs []model.Event) error {
	if len(evs) == 0 {
		return nil
	}
	var line []byte
	for i, ev := range evs {
		b, err := json.Marshal(ev)
		if err != nil {
			return err
		}
		if i > 0 {
			line = append(line, '\n')
		}
		line = append(line, b...)
	}
	f, err := os.OpenFile(s.p("events.jsonl"), os.O_CREATE|os.O_RDWR|os.O_APPEND, 0o600)
	if err != nil {
		return err
	}
	defer f.Close()
	fi, err := f.Stat()
	if err != nil {
		return err
	}
	size := fi.Size()
	var out []byte
	if size > 0 {
		last := make([]byte, 1)
		if _, err := f.ReadAt(last, size-1); err != nil {
			return err
		}
		if last[0] != '\n' {
			cut, err := lastLineStart(f, size)
			if err != nil {
				return err
			}
			frag := make([]byte, size-cut)
			if _, err := f.ReadAt(frag, cut); err != nil && err != io.EOF {
				return err
			}
			if _, ok := parseEvent(bytes.TrimSpace(frag)); ok {
				out = append(out, '\n')
			} else {
				if err := f.Truncate(cut); err != nil { // MUT:heal
					return err
				}
				size = cut
			}
		}
	}
	out = append(append(out, line...), '\n')
	if _, err := f.Write(out); err != nil {
		return err
	}
	if err := fsyncFile(f); err != nil { // MUT:logsync
		return err
	}
	r.Index.Ino = inode(fi)
	r.Index.Off = size + int64(len(out))
	r.Index.Events += len(evs)
	return nil
}

func cleanPtr(p *string, max int) { *p = label.Clean(*p, max) }

// prepare validates ids and sanitises every free-text field of an event
// before it is sequenced and logged (review finding 2), and records the pid
// start identity (finding 8).
func (s *Store) prepare(ev *model.Event) error {
	switch ev.Type {
	case model.EvRegister:
		if ev.Entity == nil {
			return errors.New("register: entity with id required")
		}
		e := *ev.Entity
		if !label.ValidID(e.ID) { // MUT:validid
			return fmt.Errorf("register: invalid id %q (want %s)", e.ID, idGrammar)
		}
		for k, v := range map[string]string{"parent_id": e.ParentID, "session_id": e.SessionID} {
			if v != "" && !label.ValidID(v) {
				return fmt.Errorf("register: invalid %s %q", k, v)
			}
		}
		for _, f := range []*string{&e.Track, &e.Branch, &e.Alias, &e.Model, &e.Effort, &e.Source, &e.PIDStart} {
			cleanPtr(f, label.MaxFieldRunes)
		}
		if e.PID < 0 || e.PID > MaxPID { // MUT:pidrange
			return fmt.Errorf("register: invalid pid %d (want 0..%d)", e.PID, MaxPID)
		}
		cleanPtr(&e.Host, maxHostRunes)
		cleanPtr(&e.Cwd, maxCwdRunes)
		if e.PID > 0 && e.PIDStart == "" && (e.Host == "" || e.Host == s.opts.LocalHost) {
			e.PIDStart = s.opts.Pids.Start(e.PID)
		}
		ev.Entity = &e
	case model.EvUpdate, model.EvHeartbeat, model.EvUnregister, model.EvReap:
		if !label.ValidID(ev.ID) {
			return fmt.Errorf("%s: invalid id %q", ev.Type, ev.ID)
		}
		if len(ev.Patch) > 0 {
			p := make(map[string]string, len(ev.Patch))
			for k, v := range ev.Patch {
				switch k {
				case "cwd":
					v = label.Clean(v, maxCwdRunes)
				case "host":
					v = label.Clean(v, maxHostRunes)
				case "parent_id", "session_id":
					// never passed through unchecked (review-2 finding 9)
					if v != "" && !label.ValidID(v) { // MUT:patchid
						return fmt.Errorf("%s: invalid %s %q (want %s)", ev.Type, k, label.Clean(v, 160), idGrammar)
					}
				case "pid":
					if v != "" {
						if n, err := strconv.Atoi(v); err != nil || n < 0 || n > MaxPID {
							return fmt.Errorf("%s: invalid pid %q (want 0..%d)", ev.Type, label.Clean(v, 32), MaxPID)
						}
					}
				default:
					v = label.Clean(v, label.MaxFieldRunes)
				}
				p[k] = v
			}
			if v, ok := p["pid"]; ok {
				if _, given := p["pid_start"]; !given {
					n, _ := strconv.Atoi(v)
					p["pid_start"] = ""
					if n > 0 {
						p["pid_start"] = s.opts.Pids.Start(n)
					}
				}
			}
			ev.Patch = p
		}
	case model.EvAliasSwitch:
		if ev.Active != nil {
			a := *ev.Active
			cleanPtr(&a.Alias, label.MaxFieldRunes)
			cleanPtr(&a.Model, label.MaxFieldRunes)
			cleanPtr(&a.Effort, label.MaxFieldRunes)
			ev.Active = &a
		}
	}
	return nil
}

const idGrammar = `^[A-Za-z0-9._:@/-]{1,160}$`

// applyOn validates, sequences, folds and logs one event onto r (the caller
// holds the lock and persists afterwards). A rejected event is not logged.
func (s *Store) applyOn(r *Raw, ev model.Event) (model.Event, error) {
	if err := s.prepare(&ev); err != nil {
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
	return ev, s.appendEvent(r, ev)
}

// reapLocked opportunistically reaps `done` entities past retention so the
// snapshot stays bounded even with label-busd down (review finding 5(v)), and
// SWEEPS kill -9 / power-cycle leftovers (review-2 finding 7): an entity that
// is not done, runs on THIS host with a recorded pid whose process is provably
// gone (same pid AND start identity no longer alive — the staleness rule's
// proof), and has not been updated for SweepAfter is removed. Pid-less and
// remote entities are never swept (their liveness cannot be proven). At most
// SweepBatch entities go per transaction, appended with one fsync, so the
// lock hold stays bounded; later writes continue the sweep.
func (s *Store) reapLocked(r *Raw) ([]string, error) {
	now := s.opts.Now()
	var ids []string
	var swept []string
	for id, e := range r.Entities {
		if e.State == model.StateDone && now.Sub(e.UpdatedAt) > s.opts.DoneRetention { // MUT:reap
			ids = append(ids, id)
			continue
		}
		if s.sweepable(e, now) {
			swept = append(swept, id)
		}
	}
	sort.Strings(swept)
	if len(swept) > s.opts.SweepBatch { // MUT:sweepbatch
		swept = swept[:s.opts.SweepBatch]
	}
	ids = append(ids, swept...)
	sort.Strings(ids)
	evs := make([]model.Event, 0, len(ids))
	for _, id := range ids {
		ev := model.Event{Type: model.EvReap, ID: id, Seq: r.Seq + 1, TS: now}
		if err := r.Apply(ev); err != nil {
			return nil, err
		}
		evs = append(evs, ev)
	}
	if err := s.appendEvents(r, evs); err != nil {
		return nil, err
	}
	return ids, nil
}

// sweepable: see reapLocked. Never true for a live, pid-less, remote, done or
// recently-updated entity, nor when the sweeper is disabled (SweepAfter < 0).
func (s *Store) sweepable(e *model.Entity, now time.Time) bool {
	if s.opts.SweepAfter < 0 || e.State == model.StateDone || e.PID <= 0 {
		return false
	}
	if e.Host != "" && e.Host != s.opts.LocalHost {
		return false
	}
	if !(now.Sub(e.UpdatedAt) > s.opts.SweepAfter) { // MUT:sweepage
		return false
	}
	return !s.opts.Pids.Alive(e.PID, e.PIDStart) // MUT:sweepalive
}

func (s *Store) lock() (*lockFile, error) { return acquire(s.p("lock"), s.opts.LockTimeout) }

// Apply validates, sequences, logs and folds one event; it assigns Seq and
// TS. A rejected event is not logged. Past-retention done entities are reaped
// in the same transaction and the log is compacted when over its bound.
func (s *Store) Apply(ev model.Event) (model.Event, error) {
	lk, err := s.lock()
	if err != nil {
		return ev, err
	}
	defer lk.release()
	r, err := s.load()
	if err != nil {
		return ev, err
	}
	out, err := s.applyOn(r, ev)
	if err != nil {
		return out, err
	}
	if _, err := s.reapLocked(r); err != nil {
		return out, err
	}
	if err := s.persist(r); err != nil {
		return out, err
	}
	s.maybeCompact(r)
	return out, nil
}

// ------------------------------------------------------------- compaction

// maybeCompact compacts when the log is over its bound. A failure never
// fails the caller's (already durable) event: it is recorded in
// compact.failed, which Verify reports while the log stays over its bound,
// and is retried on every following write.
func (s *Store) maybeCompact(r *Raw) {
	if r.Index.Events <= s.opts.CompactEvents && r.Index.Off <= s.opts.CompactBytes {
		_ = os.Remove(s.p("compact.failed")) // the log is within bounds again
		return
	}
	if err := s.compact(r); err != nil {
		_ = WriteAtomic(s.p("compact.failed"), []byte(label.CleanText(err.Error())+"\n"))
		return
	}
	_ = os.Remove(s.p("compact.failed"))
}

// compact folds all but the last KeepTail events into base.json and rotates
// events.jsonl down to that tail. Order, each step atomic and fsynced:
//  1. base.json  (state at seq B)            — log still complete: no loss
//  2. events.jsonl replaced by the tail B+1.. — base+tail == previous state
//  3. fold.json  with the new offset index    — a crash before it only costs
//     one full (bounded) read
//
// A kill -9 between any two steps leaves a state every reader and writer
// recovers from (events <= base seq in an old log are skipped).
func (s *Store) compact(r *Raw) error {
	base, err := s.readBase()
	if err != nil {
		return err
	}
	f, err := os.Open(s.p("events.jsonl"))
	if err != nil {
		return err
	}
	res, err := scanLog(f, 0)
	f.Close()
	if err != nil {
		return err
	}
	if res.corrupt > 0 {
		return fmt.Errorf("compaction refused: events.jsonl has %d corrupt line(s) (run labelctl verify)", res.corrupt)
	}
	var evs []model.Event
	for _, ev := range res.evs {
		if ev.Seq > base.Seq {
			evs = append(evs, ev)
		}
	}
	if len(evs) > 0 && evs[0].Seq != base.Seq+1 {
		return fmt.Errorf("compaction refused: log starts at seq %d, base at %d", evs[0].Seq, base.Seq)
	}
	if len(evs) <= s.opts.KeepTail {
		return nil
	}
	drop, tail := evs[:len(evs)-s.opts.KeepTail], evs[len(evs)-s.opts.KeepTail:]
	nb := base
	replay(nb, drop)
	nb.Index = logIndex{}
	bb, err := json.Marshal(nb)
	if err != nil {
		return err
	}
	if err := WriteAtomic(s.p("base.json"), bb); err != nil { // MUT:compactbase
		return err
	}
	if err := s.step("compact:base"); err != nil {
		return err
	}
	var buf bytes.Buffer
	for _, ev := range tail {
		b, err := json.Marshal(ev)
		if err != nil {
			return err
		}
		buf.Write(b)
		buf.WriteByte('\n')
	}
	if err := WriteAtomic(s.p("events.jsonl"), buf.Bytes()); err != nil {
		return err
	}
	if err := s.step("compact:log"); err != nil {
		return err
	}
	fi, err := os.Stat(s.p("events.jsonl"))
	if err != nil {
		return err
	}
	r.Index = logIndex{Ino: inode(fi), Off: fi.Size(), Events: len(tail), BaseSeq: nb.Seq}
	fb, err := json.Marshal(r)
	if err != nil {
		return err
	}
	if err := WriteAtomic(s.p("fold.json"), fb); err != nil {
		return err
	}
	return s.step("compact:fold")
}

// ------------------------------------------------------------------ reads

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

// Seq returns the highest event sequence.
func (s *Store) Seq() (uint64, error) {
	r, err := s.load()
	if err != nil {
		return 0, err
	}
	return r.Seq, nil
}

// EventsSince returns events with Seq > seq, in order, reading events.jsonl
// BACKWARDS from its end only as far as needed (a poller one event behind
// reads one chunk). When seq predates the compaction horizon, the result
// starts with ONE synthetic `reconcile` event at the horizon (the compacted
// events are gone; the consumer must re-read snapshot.json).
func (s *Store) EventsSince(seq uint64) ([]model.Event, error) {
	f, err := os.Open(s.p("events.jsonl"))
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	defer f.Close()
	fi, err := f.Stat()
	if err != nil {
		return nil, err
	}
	var rev []model.Event
	var carry []byte
	found := false
	buf := make([]byte, 64<<10)
	for pos := fi.Size(); pos > 0 && !found; {
		n := int64(len(buf))
		if n > pos {
			n = pos
		}
		pos -= n
		if _, err := f.ReadAt(buf[:n], pos); err != nil && err != io.EOF {
			return nil, err
		}
		data := append(append([]byte(nil), buf[:n]...), carry...)
		lines := bytes.Split(data, []byte{'\n'})
		start := 0
		carry = nil
		if pos > 0 {
			carry, start = lines[0], 1
		}
		for i := len(lines) - 1; i >= start; i-- {
			ev, ok := parseEvent(bytes.TrimSpace(lines[i]))
			if !ok {
				continue
			}
			if ev.Seq <= seq {
				found = true
				break
			}
			rev = append(rev, ev)
		}
	}
	out := make([]model.Event, 0, len(rev)+1)
	for i := len(rev) - 1; i >= 0; i-- {
		out = append(out, rev[i])
	}
	if !found && len(out) > 0 && out[0].Seq > seq+1 { // MUT:horizon
		gap := model.Event{Seq: out[0].Seq - 1, TS: s.opts.Now(), Type: model.EvReconcile}
		out = append([]model.Event{gap}, out...)
	}
	return out, nil
}

// Reconcile is the level-triggered convergence step (§11.4.233): reap done
// entities past retention, then, if the rendered view differs from the
// published snapshot.json (e.g. an entity just went stale), bump seq and
// republish. Idempotent: running it twice in a row changes nothing.
func (s *Store) Reconcile() (changed bool, reaped []string, err error) {
	lk, err := s.lock()
	if err != nil {
		return false, nil, err
	}
	defer lk.release()
	r, err := s.load()
	if err != nil {
		return false, nil, err
	}
	if reaped, err = s.reapLocked(r); err != nil {
		return len(reaped) > 0, reaped, err
	}
	changed = len(reaped) > 0
	if !changed {
		want := Render(r, s.renderOpts())
		var have model.Snapshot
		if b, rerr := os.ReadFile(s.p("snapshot.json")); rerr != nil || json.Unmarshal(b, &have) != nil ||
			!reflect.DeepEqual(normalise(have), normalise(want)) {
			if _, err := s.applyOn(r, model.Event{Type: model.EvReconcile}); err != nil {
				return false, nil, err
			}
			changed = true
		}
	}
	if changed {
		if err := s.persist(r); err != nil {
			return changed, reaped, err
		}
		s.maybeCompact(r)
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

// Verify checks the on-disk files for consistency: base.json + log parseable
// (a torn final line is fine) and contiguous, fold.json equals base+log
// replay and is not ahead, snapshot.json and the seq file are not ahead, and
// no compaction failure is pending.
func (s *Store) Verify() error {
	var probs []string
	base, err := s.readBase()
	if err != nil {
		probs = append(probs, err.Error())
		base = NewRaw()
	}
	var res scanResult
	if f, err := os.Open(s.p("events.jsonl")); err == nil {
		res, err = scanLog(f, 0)
		f.Close()
		if err != nil {
			return err
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if res.corrupt > 0 {
		probs = append(probs, fmt.Sprintf("events.jsonl: %d corrupt non-final line(s)", res.corrupt))
	}
	var prev uint64
	var tail []model.Event
	for _, ev := range res.evs {
		if ev.Seq <= prev {
			probs = append(probs, fmt.Sprintf("events.jsonl: non-monotonic seq %d after %d", ev.Seq, prev))
		}
		prev = ev.Seq
		if ev.Seq > base.Seq {
			tail = append(tail, ev)
		}
	}
	if len(tail) > 0 && tail[0].Seq > base.Seq+1 {
		probs = append(probs, fmt.Sprintf("events.jsonl starts at seq %d but base.json is at seq %d (history missing)", tail[0].Seq, base.Seq))
	}
	want := base
	replay(want, tail)
	last := want.Seq
	if b, err := s.readJSONRaw("fold.json"); err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			probs = append(probs, "fold.json unparseable")
		} else if last > 0 {
			probs = append(probs, "fold.json missing")
		}
	} else if b.Seq > last {
		probs = append(probs, "fold.json is ahead of the event log")
	} else if b.Seq == want.Seq && !reflect.DeepEqual(canon(b), canon(want)) { // MUT:verifyfold
		probs = append(probs, "fold.json differs from replay of base.json+events.jsonl")
	}
	if b, err := os.ReadFile(s.p("snapshot.json")); err != nil {
		if last > 0 {
			probs = append(probs, "snapshot.json missing")
		}
	} else {
		var sn model.Snapshot
		if json.Unmarshal(b, &sn) != nil {
			probs = append(probs, "snapshot.json unparseable (torn/truncated)")
		} else if sn.Seq > last { // MUT:verifysnap
			probs = append(probs, "snapshot.json is ahead of the event log")
		}
	}
	if b, err := os.ReadFile(s.p("seq")); err == nil {
		n, perr := strconv.ParseUint(strings.TrimSpace(string(b)), 10, 64)
		if perr != nil {
			probs = append(probs, "seq file unparseable")
		} else if n > last { // MUT:verifyseq
			probs = append(probs, "seq file is ahead of the event log")
		}
	}
	if b, err := os.ReadFile(s.p("compact.failed")); err == nil {
		probs = append(probs, "last compaction failed: "+strings.TrimSpace(string(b)))
	}
	if len(probs) > 0 {
		return errors.New(strings.Join(probs, "; "))
	}
	return nil
}

func canon(r *Raw) any {
	c := *r
	c.Index = logIndex{}
	b, _ := json.Marshal(&c)
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

// OptionsFromEnv builds Options from LABEL_SYNC_DIR, LABEL_SYNC_TTL,
// LABEL_SYNC_DONE_RETENTION, LABEL_SYNC_LOCK_TIMEOUT (Go durations like
// "90s", or bare seconds), LABEL_SYNC_COMPACT_EVENTS and
// LABEL_SYNC_COMPACT_BYTES (integers), LABEL_SYNC_STALE_SWEEP (duration, or
// "off") and LABEL_SYNC_SWEEP_BATCH (integer).
func OptionsFromEnv() Options {
	o := Options{Dir: os.Getenv("LABEL_SYNC_DIR")}
	o.TTL = envDur("LABEL_SYNC_TTL")
	o.DoneRetention = envDur("LABEL_SYNC_DONE_RETENTION")
	o.LockTimeout = envDur("LABEL_SYNC_LOCK_TIMEOUT")
	if n, err := strconv.Atoi(os.Getenv("LABEL_SYNC_COMPACT_EVENTS")); err == nil {
		o.CompactEvents = n
	}
	if n, err := strconv.ParseInt(os.Getenv("LABEL_SYNC_COMPACT_BYTES"), 10, 64); err == nil {
		o.CompactBytes = n
	}
	if v := strings.TrimSpace(os.Getenv("LABEL_SYNC_STALE_SWEEP")); v == "off" {
		o.SweepAfter = -1
	} else if d, ok := ParseDuration(v); ok && d > 0 {
		o.SweepAfter = d
	}
	if n, err := strconv.Atoi(os.Getenv("LABEL_SYNC_SWEEP_BATCH")); err == nil {
		o.SweepBatch = n
	}
	return o
}

// ParseDuration accepts a Go duration ("500ms", "2s") or bare seconds.
func ParseDuration(v string) (time.Duration, bool) {
	if d, err := time.ParseDuration(v); err == nil {
		return d, true
	}
	if f, err := strconv.ParseFloat(v, 64); err == nil {
		return time.Duration(f * float64(time.Second)), true
	}
	return 0, false
}

func envDur(k string) time.Duration {
	d, _ := ParseDuration(os.Getenv(k))
	return d
}
