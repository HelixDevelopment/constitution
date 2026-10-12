package state

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
)

func newCompactStore(t *testing.T, dir string, every, keep int) (*Store, *clock) {
	t.Helper()
	c := &clock{t: time.Date(2026, 10, 12, 10, 0, 0, 0, time.UTC)}
	s, err := Open(Options{Dir: dir, Now: c.Now, Pids: fakePids{}, TTL: time.Hour, DoneRetention: time.Hour,
		LocalHost: "h1", CompactEvents: every, KeepTail: keep})
	if err != nil {
		t.Fatal(err)
	}
	return s, c
}

func countLines(t *testing.T, p string) int {
	t.Helper()
	return strings.Count(readFile(t, p), "\n")
}

// Finding 5(i): the log is compacted past its bound; seq stays monotonic and
// the logical state is unchanged; Verify stays clean.
func TestCompactionBoundsLogKeepsStateAndSeq(t *testing.T) {
	s, _ := newCompactStore(t, t.TempDir(), 50, 10)
	switchAlias(t, s, "claude1", "opus", "high")
	for i := 0; i < 400; i++ {
		reg(t, s, model.Entity{ID: fmt.Sprintf("e%d", i%30), Kind: "shell", Branch: fmt.Sprint(i)})
	}
	if n := countLines(t, s.p("events.jsonl")); n > 51 {
		t.Fatalf("log not bounded: %d lines", n)
	}
	if _, err := os.Stat(s.p("base.json")); err != nil {
		t.Fatalf("base.json missing after compaction: %v", err)
	}
	if seq, _ := s.Seq(); seq != 401 {
		t.Fatalf("seq after compaction = %d, want 401", seq)
	}
	snap, _ := s.Snapshot()
	if len(snap.Entities) != 30 || snap.Active.Alias != "claude1" {
		t.Fatalf("state lost: %d entities active=%q", len(snap.Entities), snap.Active.Alias)
	}
	if e := get(t, s, "e9"); e.Branch != "399" {
		t.Fatalf("latest value lost: %+v", e)
	}
	if err := s.Verify(); err != nil {
		t.Fatalf("verify after compaction: %v", err)
	}
	out, err := s.Apply(model.Event{Type: model.EvHeartbeat, ID: "e1"})
	if err != nil || out.Seq != 402 {
		t.Fatalf("next seq %d err=%v", out.Seq, err)
	}
	// a subscriber behind the horizon gets ONE synthetic reconcile marker,
	// then the retained tail, in order.
	evs, err := s.EventsSince(0)
	if err != nil || len(evs) == 0 || evs[0].Type != model.EvReconcile {
		t.Fatalf("horizon marker missing: %v %+v", err, evs)
	}
	for i := 1; i < len(evs); i++ {
		if evs[i].Seq != evs[i-1].Seq+1 {
			t.Fatalf("non-contiguous tail at %d: %d after %d", i, evs[i].Seq, evs[i-1].Seq)
		}
	}
	if evs[len(evs)-1].Seq != 402 {
		t.Fatalf("tail does not end at head: %d", evs[len(evs)-1].Seq)
	}
	// a subscriber inside the tail gets exactly the newer events, no marker
	if evs, _ := s.EventsSince(400); len(evs) != 2 || evs[0].Seq != 401 || evs[1].Seq != 402 {
		t.Fatalf("EventsSince(400) = %+v", evs)
	}
	if evs, _ := s.EventsSince(402); len(evs) != 0 {
		t.Fatalf("EventsSince(head) = %+v", evs)
	}
}

// Finding 5(i): kill -9 at EVERY durable step of compaction (and of persist)
// leaves a recoverable state: a fresh process sees the same logical state,
// verify passes after the next write, seq is monotonic, nothing acked lost.
func TestCompactionCrashAtEveryStepIsRecoverable(t *testing.T) {
	points := []string{"persist:fold", "persist:snapshot", "persist:active", "persist:seq", "compact:base", "compact:log", "compact:fold"}
	for _, pt := range points {
		t.Run(pt, func(t *testing.T) {
			dir := t.TempDir()
			s, _ := newCompactStore(t, dir, 40, 5)
			for i := 0; i < 39; i++ {
				reg(t, s, model.Entity{ID: fmt.Sprintf("e%d", i), Kind: "shell"})
			}
			crash := errors.New("kill -9 at " + pt)
			armed := true
			s.hook = func(p string) error {
				if armed && p == pt {
					armed = false
					return crash
				}
				return nil
			}
			// event 40 + 41 push the log over the bound -> compaction
			e := model.Entity{ID: "crash-me", Kind: "shell"}
			_, err1 := s.Apply(model.Event{Type: model.EvRegister, Entity: &e})
			e2 := model.Entity{ID: "after", Kind: "shell"}
			_, err2 := s.Apply(model.Event{Type: model.EvRegister, Entity: &e2})
			if armed {
				t.Fatalf("step %s never reached (err1=%v err2=%v)", pt, err1, err2)
			}
			// fresh process
			s2, _ := newCompactStore(t, dir, 40, 5)
			snap, err := s2.Snapshot()
			if err != nil {
				t.Fatal(err)
			}
			have := map[string]bool{}
			for _, x := range snap.Entities {
				have[x.ID] = true
			}
			for i := 0; i < 39; i++ {
				if !have[fmt.Sprintf("e%d", i)] {
					t.Fatalf("acked e%d lost after crash at %s", i, pt)
				}
			}
			if !have["crash-me"] || !have["after"] {
				t.Fatalf("durably-logged events lost after crash at %s: %v", pt, have)
			}
			before := snap.Seq
			e3 := model.Entity{ID: "heal", Kind: "shell"}
			out, err := s2.Apply(model.Event{Type: model.EvRegister, Entity: &e3})
			if err != nil || out.Seq != before+1 {
				t.Fatalf("seq not monotonic after crash at %s: %d -> %d (%v)", pt, before, out.Seq, err)
			}
			if err := s2.Verify(); err != nil {
				t.Fatalf("verify after recovery from %s: %v", pt, err)
			}
		})
	}
}

// Finding 5(v): writers reap past-retention done entities without label-busd.
func TestWritersReapPastRetentionDone(t *testing.T) {
	s, c, _ := newStore(t) // retention 5 min
	for i := 0; i < 50; i++ {
		id := fmt.Sprintf("cmd%d", i)
		reg(t, s, model.Entity{ID: id, Kind: "command"})
		if _, err := s.Apply(model.Event{Type: model.EvUnregister, ID: id}); err != nil {
			t.Fatal(err)
		}
	}
	c.Add(6 * time.Minute)
	reg(t, s, model.Entity{ID: "live", Kind: "shell"})
	snap, _ := s.Snapshot()
	if len(snap.Entities) != 1 || snap.Entities[0].ID != "live" {
		t.Fatalf("done entities not reaped by a writer: %d left", len(snap.Entities))
	}
	if err := s.Verify(); err != nil {
		t.Fatal(err)
	}
}

// Hook-review finding 9: lock acquisition is bounded.
func TestLockTimeoutIsBounded(t *testing.T) {
	dir := t.TempDir()
	s, err := Open(Options{Dir: dir, Pids: fakePids{}, LockTimeout: 150 * time.Millisecond})
	if err != nil {
		t.Fatal(err)
	}
	f, err := os.OpenFile(filepath.Join(dir, "lock"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		t.Fatal(err)
	}
	t0 := time.Now()
	e := model.Entity{ID: "x", Kind: "shell"}
	_, err = s.Apply(model.Event{Type: model.EvRegister, Entity: &e})
	el := time.Since(t0)
	if !errors.Is(err, ErrLockTimeout) {
		t.Fatalf("want ErrLockTimeout, got %v", err)
	}
	if el < 140*time.Millisecond || el > 2*time.Second {
		t.Fatalf("timeout not honoured: %v", el)
	}
	_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
	if _, err := s.Apply(model.Event{Type: model.EvRegister, Entity: &e}); err != nil {
		t.Fatalf("after release: %v", err)
	}
}

// Finding 9: every durable write goes through fsync; an fsync failure is NOT
// acknowledged and leaves the destination intact.
func TestFsyncIsCalledAndFailuresPropagate(t *testing.T) {
	var mu sync.Mutex
	calls := 0
	fail := ""
	orig := fsyncFile
	t.Cleanup(func() { fsyncFile = orig })
	fsyncFile = func(f *os.File) error {
		mu.Lock()
		defer mu.Unlock()
		calls++
		if fail != "" && strings.Contains(f.Name(), fail) {
			return errors.New("injected EIO on " + f.Name())
		}
		return f.Sync()
	}
	s, _, _ := newStore(t)
	reg(t, s, model.Entity{ID: "a", Kind: "shell"})
	if calls < 5 { // log + 4 temp files (+ dirs)
		t.Fatalf("fsync called only %d times for one write", calls)
	}
	fail = "events.jsonl"
	e := model.Entity{ID: "b", Kind: "shell"}
	if _, err := s.Apply(model.Event{Type: model.EvRegister, Entity: &e}); err == nil {
		t.Fatal("log fsync failure must fail the write (not acknowledged)")
	}
	fail = ".snapshot.json.tmp-"
	before := readFile(t, s.p("snapshot.json"))
	e = model.Entity{ID: "c", Kind: "shell"}
	if _, err := s.Apply(model.Event{Type: model.EvRegister, Entity: &e}); err == nil {
		t.Fatal("snapshot temp fsync failure must surface")
	}
	if got := readFile(t, s.p("snapshot.json")); got != before {
		t.Fatal("snapshot.json replaced although its fsync failed")
	}
}

// Finding 9 (stress reader): at every step of persist, a lock-free reader that
// sees seq N can read a snapshot at >= N (kills "seq written first").
func TestSeqNeverAheadOfSnapshotDuringPersist(t *testing.T) {
	s, _, _ := newStore(t)
	reg(t, s, model.Entity{ID: "a", Kind: "shell"})
	bad := ""
	s.hook = func(p string) error {
		n := s.PeekSeq()
		var sn model.Snapshot
		if b, err := os.ReadFile(s.p("snapshot.json")); err == nil {
			if err := jsonUnmarshal(b, &sn); err == nil && sn.Seq < n && bad == "" {
				bad = fmt.Sprintf("after %s: seq file %d > snapshot %d", p, n, sn.Seq)
			}
		}
		return nil
	}
	for i := 0; i < 5; i++ {
		reg(t, s, model.Entity{ID: fmt.Sprintf("x%d", i), Kind: "shell"})
	}
	if bad != "" {
		t.Fatal(bad)
	}
}

// Finding 2 at the store boundary: ids are validated, text is sanitised
// before it reaches the log (so bash `jq -r` readers are safe too).
func TestStoreRejectsBadIDsAndSanitisesText(t *testing.T) {
	s, _, _ := newStore(t)
	for _, id := range []string{"id\x1b]0;X\x07", "", "has space", strings.Repeat("a", 161), "ü"} {
		e := model.Entity{ID: id, Kind: "shell"}
		if _, err := s.Apply(model.Event{Type: model.EvRegister, Entity: &e}); err == nil {
			t.Errorf("id %q accepted", id)
		}
	}
	e := model.Entity{ID: "ok", Kind: "shell", ParentID: "bad\x1bparent"}
	if _, err := s.Apply(model.Event{Type: model.EvRegister, Entity: &e}); err == nil {
		t.Error("bad parent id accepted")
	}
	reg(t, s, model.Entity{ID: "ok", Kind: "shell", Branch: "b\x1b]52;c;aGk=\x07r", Alias: "a‮x", Cwd: "/tmp/\x9bx"})
	if _, err := s.Apply(model.Event{Type: model.EvUpdate, ID: "ok", Patch: map[string]string{"model": "m\x1b[2Jz"}}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Apply(model.Event{Type: model.EvAliasSwitch, Active: &model.Active{Alias: "c\x1b1"}}); err != nil {
		t.Fatal(err)
	}
	for _, f := range []string{"events.jsonl", "snapshot.json", "active.json", "fold.json"} {
		b := readFile(t, s.p(f))
		if strings.Contains(b, `\u001b`) || strings.Contains(b, "\x1b") || strings.Contains(b, "‮") || strings.Contains(b, `‮`) {
			t.Fatalf("%s carries a control/bidi char: %s", f, b)
		}
	}
	if l := get(t, s, "ok").Label; strings.ContainsAny(l, "\x1b‮") {
		t.Fatalf("label %q", l)
	}
}

// Finding 10: an existing state dir is forced to 0700; a dir owned by another
// uid is refused; orphaned temp files are cleaned at open.
func TestOpenEnforcesModeOwnerAndCleansOrphans(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "st")
	if err := os.Mkdir(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	old := filepath.Join(dir, ".snapshot.json.tmp-123")
	fresh := filepath.Join(dir, ".seq.tmp-456")
	writeFile(t, old, "x")
	writeFile(t, fresh, "x")
	past := time.Now().Add(-time.Hour)
	_ = os.Chtimes(old, past, past)
	if _, err := Open(Options{Dir: dir, Pids: fakePids{}}); err != nil {
		t.Fatal(err)
	}
	fi, _ := os.Stat(dir)
	if fi.Mode().Perm() != 0o700 {
		t.Fatalf("mode %v, want 0700", fi.Mode().Perm())
	}
	if _, err := os.Stat(old); !os.IsNotExist(err) {
		t.Fatal("orphaned temp file older than a minute not removed")
	}
	if _, err := os.Stat(fresh); err != nil {
		t.Fatal("a FRESH temp file (possibly in flight) must not be removed")
	}
	orig := currentUID
	t.Cleanup(func() { currentUID = orig })
	currentUID = func() int { return os.Getuid() + 1 }
	if _, err := Open(Options{Dir: dir, Pids: fakePids{}}); err == nil {
		t.Fatal("state dir owned by another uid must be refused")
	}
}

// Finding 8: pid reuse — liveness compares the recorded start identity, a
// recycled pid is dead, EPERM is never alive without a start match.
func fakeProc(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "sys", "kernel", "random"), 0o700); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(root, "sys", "kernel", "random", "boot_id"), "boot-1\n")
	return root
}

func setProc(t *testing.T, root string, pid int, start string) {
	t.Helper()
	d := filepath.Join(root, fmt.Sprint(pid))
	_ = os.MkdirAll(d, 0o700)
	// comm with spaces and a ')' to exercise last-paren parsing
	writeFile(t, filepath.Join(d, "stat"), fmt.Sprintf("%d (we ird) x) S 1 1 1 0 -1 4194560 0 0 0 0 0 0 0 0 20 0 1 0 %s 1 1\n", pid, start))
}

func TestPidReuseIsNotAlive(t *testing.T) {
	root := fakeProc(t)
	setProc(t, root, 42, "1000")
	p := ProcPids{Root: root, Kill: func(int, syscall.Signal) error { return nil }}
	st := p.Start(42)
	if st != "boot-1:1000" {
		t.Fatalf("Start = %q", st)
	}
	if !p.Alive(42, st) {
		t.Fatal("same process must be alive")
	}
	setProc(t, root, 42, "2000") // pid recycled by a new process
	if p.Alive(42, st) {
		t.Fatal("recycled pid must NOT be alive")
	}
	if !p.Alive(42, "") {
		t.Fatal("legacy entity without start: existing pid counts as alive")
	}
	os.RemoveAll(filepath.Join(root, "42"))
	if p.Alive(42, "") || p.Alive(42, st) {
		t.Fatal("missing /proc/<pid> must be dead")
	}
	// no /proc at all (other OS): EPERM never alive; nil only without a start
	np := ProcPids{Root: filepath.Join(root, "absent"), Kill: func(int, syscall.Signal) error { return syscall.EPERM }}
	if np.Alive(7, "") || np.Alive(7, "boot-1:1") {
		t.Fatal("EPERM must not mean alive")
	}
	np.Kill = func(int, syscall.Signal) error { return nil }
	if !np.Alive(7, "") || np.Alive(7, "boot-1:1") {
		t.Fatal("kill==nil is alive only when no start must be matched")
	}
}

// The store records the start identity at register and uses it for staleness.
func TestStoreRecordsPidStartAndStalenessUsesIt(t *testing.T) {
	root := fakeProc(t)
	setProc(t, root, 77, "5")
	c := &clock{t: time.Date(2026, 10, 12, 10, 0, 0, 0, time.UTC)}
	s, err := Open(Options{Dir: t.TempDir(), Now: c.Now, Pids: ProcPids{Root: root}, TTL: time.Minute, LocalHost: "h1"})
	if err != nil {
		t.Fatal(err)
	}
	reg(t, s, model.Entity{ID: "p", Kind: "shell", PID: 77, Host: "h1"})
	if e := get(t, s, "p"); e.PIDStart != "boot-1:5" {
		t.Fatalf("pid_start not recorded: %+v", e)
	}
	c.Add(2 * time.Minute)
	if get(t, s, "p").Stale {
		t.Fatal("same live process must not be stale")
	}
	setProc(t, root, 77, "999") // recycled
	if !get(t, s, "p").Stale {
		t.Fatal("recycled pid must not keep the entity alive")
	}
}
