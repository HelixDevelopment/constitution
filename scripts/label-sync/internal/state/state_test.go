package state

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/label"
	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
)

type fakePids map[int]bool

func (f fakePids) Alive(pid int, _ string) bool { return f[pid] }
func (f fakePids) Start(int) string             { return "" }

type clock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *clock) Now() time.Time { c.mu.Lock(); defer c.mu.Unlock(); return c.t }
func (c *clock) Add(d time.Duration) {
	c.mu.Lock()
	c.t = c.t.Add(d)
	c.mu.Unlock()
}

func newStore(t *testing.T) (*Store, *clock, fakePids) {
	t.Helper()
	c := &clock{t: time.Date(2026, 10, 12, 10, 0, 0, 0, time.UTC)}
	p := fakePids{}
	s, err := Open(Options{Dir: t.TempDir(), Now: c.Now, Pids: p, TTL: 2 * time.Minute, DoneRetention: 5 * time.Minute, LocalHost: "h1"})
	if err != nil {
		t.Fatal(err)
	}
	return s, c, p
}

func reg(t *testing.T, s *Store, e model.Entity) {
	t.Helper()
	if _, err := s.Apply(model.Event{Type: model.EvRegister, Entity: &e}); err != nil {
		t.Fatalf("register %s: %v", e.ID, err)
	}
}

func switchAlias(t *testing.T, s *Store, alias, mo, ef string) {
	t.Helper()
	if _, err := s.Apply(model.Event{Type: model.EvAliasSwitch, Active: &model.Active{Alias: alias, Model: mo, Effort: ef}}); err != nil {
		t.Fatal(err)
	}
}

func get(t *testing.T, s *Store, id string) model.Entity {
	t.Helper()
	snap, err := s.Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range snap.Entities {
		if e.ID == id {
			return e
		}
	}
	t.Fatalf("entity %s not in snapshot", id)
	return model.Entity{}
}

func TestRegisterRendersLabelAndFiles(t *testing.T) {
	s, _, _ := newStore(t)
	reg(t, s, model.Entity{ID: "s1", Kind: "session", Track: "2", Branch: "main", Alias: "claude1", Model: "opus", Effort: "high", PID: 10})
	e := get(t, s, "s1")
	if e.Label != "(T2/main - claude1 - opus - high)" || e.State != "running" {
		t.Fatalf("got %+v", e)
	}
	for _, f := range []string{"events.jsonl", "snapshot.json", "active.json", "seq"} {
		if _, err := os.Stat(filepath.Join(s.Dir(), f)); err != nil {
			t.Errorf("missing %s: %v", f, err)
		}
	}
	b, _ := os.ReadFile(filepath.Join(s.Dir(), "seq"))
	if strings.TrimSpace(string(b)) != "1" {
		t.Fatalf("seq file = %q", b)
	}
}

func TestValidationErrors(t *testing.T) {
	s, _, _ := newStore(t)
	cases := []struct {
		name string
		ev   model.Event
	}{
		{"no entity", model.Event{Type: model.EvRegister}},
		{"no id", model.Event{Type: model.EvRegister, Entity: &model.Entity{Kind: "shell"}}},
		{"bad kind", model.Event{Type: model.EvRegister, Entity: &model.Entity{ID: "x", Kind: "bogus"}}},
		{"update unknown", model.Event{Type: model.EvUpdate, ID: "nope", Patch: map[string]string{"alias": "a"}}},
		{"heartbeat unknown", model.Event{Type: model.EvHeartbeat, ID: "nope"}},
		{"unregister unknown", model.Event{Type: model.EvUnregister, ID: "nope"}},
		{"switch without alias", model.Event{Type: model.EvAliasSwitch, Active: &model.Active{}}},
		{"unknown type", model.Event{Type: "zzz"}},
	}
	for _, c := range cases {
		if _, err := s.Apply(c.ev); err == nil {
			t.Errorf("%s: expected error", c.name)
		}
	}
	reg(t, s, model.Entity{ID: "a", Kind: "shell"})
	for _, p := range []map[string]string{{"nokey": "x"}, {"state": "weird"}, {"pid": "abc"}, {"follow_active": "maybe"}} {
		if _, err := s.Apply(model.Event{Type: model.EvUpdate, ID: "a", Patch: p}); err == nil {
			t.Errorf("patch %v: expected error", p)
		}
	}
	// rejected events must not be logged
	evs, _ := s.EventsSince(0)
	if len(evs) != 1 {
		t.Fatalf("rejected events were logged: %d events", len(evs))
	}
}

func TestAliasSwitchFollowersAndNonFollowers(t *testing.T) {
	s, _, _ := newStore(t)
	switchAlias(t, s, "claude1", "opus", "high")
	reg(t, s, model.Entity{ID: "f1", Kind: "agent", Track: "1", Branch: "main", FollowActive: true})
	reg(t, s, model.Entity{ID: "own", Kind: "session", SessionID: "S2", Track: "1", Branch: "main", Alias: "claude9", Model: "haiku", Effort: "low"})
	reg(t, s, model.Entity{ID: "child", Kind: "subagent", ParentID: "own"})
	if l := get(t, s, "f1").Label; l != "(T1/main - claude1 - opus - high)" {
		t.Fatalf("follower before: %s", l)
	}
	switchAlias(t, s, "claude2", "sonnet", "xhigh")
	if l := get(t, s, "f1").Label; l != "(T1/main - claude2 - sonnet - xhigh)" {
		t.Fatalf("follower after switch: %s", l)
	}
	if l := get(t, s, "own").Label; l != "(T1/main - claude9 - haiku - low)" {
		t.Fatalf("non-follower must keep own alias: %s", l)
	}
	// child inherits alias + track/branch from non-follower ancestor
	if l := get(t, s, "child").Label; l != "(T1/main - claude9 - haiku - low)" {
		t.Fatalf("child inheritance: %s", l)
	}
	// the very next snapshot, no extra event needed
	snap, _ := s.Snapshot()
	if snap.Active.Alias != "claude2" {
		t.Fatalf("active %+v", snap.Active)
	}
	// active.json carries it for bash readers
	var a model.Active
	b, _ := os.ReadFile(filepath.Join(s.Dir(), "active.json"))
	if err := json.Unmarshal(b, &a); err != nil || a.Alias != "claude2" || a.Effort != "xhigh" {
		t.Fatalf("active.json %s err=%v", b, err)
	}
}

func TestFollowerWithoutActiveRendersUnknown(t *testing.T) {
	s, _, _ := newStore(t)
	reg(t, s, model.Entity{ID: "f", Kind: "stream", Track: "3", Branch: "b", FollowActive: true, Alias: "stale-own"})
	if l := get(t, s, "f").Label; l != "(T3/b - ? - ? - ?)" {
		t.Fatalf("never invent: %s", l)
	}
}

func TestSessionRegisterUnderOtherAliasRepublishesSubtree(t *testing.T) {
	s, _, _ := newStore(t)
	switchAlias(t, s, "claude1", "opus", "high")
	reg(t, s, model.Entity{ID: "c1", Kind: "agent", SessionID: "S9", Track: "1", Branch: "b", FollowActive: true})
	reg(t, s, model.Entity{ID: "mid", Kind: "agent", ParentID: "sess", Track: "1", Branch: "b", FollowActive: true})
	reg(t, s, model.Entity{ID: "leaf", Kind: "command", ParentID: "mid", FollowActive: true})
	reg(t, s, model.Entity{ID: "other", Kind: "agent", SessionID: "S1", Track: "1", Branch: "b", FollowActive: true})
	reg(t, s, model.Entity{ID: "sess", Kind: "session", SessionID: "S9", Track: "1", Branch: "b", Alias: "claude4", Model: "fable", Effort: "max"})
	for _, id := range []string{"c1", "mid", "leaf", "sess"} {
		if l := get(t, s, id).Label; !strings.Contains(l, "claude4 - fable - max") {
			t.Errorf("%s not republished: %s", id, l)
		}
	}
	if l := get(t, s, "other").Label; !strings.Contains(l, "claude1 - opus - high") {
		t.Errorf("unrelated session must keep following active: %s", l)
	}
	switchAlias(t, s, "claude3", "sonnet", "low")
	if l := get(t, s, "c1").Label; !strings.Contains(l, "claude4") {
		t.Errorf("republished subtree must stay bound to the session alias: %s", l)
	}
}

func TestStaleDeadPidRule(t *testing.T) {
	s, c, pids := newStore(t)
	pids[100] = true
	reg(t, s, model.Entity{ID: "alive", Kind: "shell", PID: 100, Track: "1", Branch: "b", Alias: "a", Model: "m", Effort: "e"})
	reg(t, s, model.Entity{ID: "dead", Kind: "shell", PID: 200, Track: "1", Branch: "b", Alias: "a", Model: "m", Effort: "e"})
	reg(t, s, model.Entity{ID: "nopid", Kind: "flow", Track: "1", Branch: "b", Alias: "a", Model: "m", Effort: "e"})
	reg(t, s, model.Entity{ID: "remote", Kind: "agent", PID: 100, Host: "other", Track: "1", Branch: "b", Alias: "a", Model: "m", Effort: "e"})
	c.Add(time.Minute) // within TTL
	for _, id := range []string{"alive", "dead", "nopid", "remote"} {
		if e := get(t, s, id); e.Stale || e.State != "running" {
			t.Fatalf("%s inside TTL must not be stale: %+v", id, e)
		}
	}
	c.Add(3 * time.Minute) // beyond TTL
	if e := get(t, s, "alive"); e.Stale || e.State != "running" {
		t.Fatalf("alive pid never stale: %+v", e)
	}
	for _, id := range []string{"dead", "nopid", "remote"} {
		e := get(t, s, id)
		if !e.Stale || e.State != "unknown" {
			t.Fatalf("%s should be stale/unknown: %+v", id, e)
		}
		if label.Validate(e.Label) != nil {
			t.Fatalf("stale label must remain grammar-valid: %q", e.Label)
		}
	}
	// stale entity is NOT deleted
	snap, _ := s.Snapshot()
	if len(snap.Entities) != 4 {
		t.Fatalf("stale entities must be retained, got %d", len(snap.Entities))
	}
	// heartbeat revives
	if _, err := s.Apply(model.Event{Type: model.EvHeartbeat, ID: "dead"}); err != nil {
		t.Fatal(err)
	}
	if e := get(t, s, "dead"); e.Stale || e.State != "running" {
		t.Fatalf("heartbeat must revive: %+v", e)
	}
	// done is never stale
	if _, err := s.Apply(model.Event{Type: model.EvUnregister, ID: "nopid"}); err != nil {
		t.Fatal(err)
	}
	c.Add(time.Hour)
	if e := get(t, s, "nopid"); e.Stale || e.State != "done" {
		t.Fatalf("done stays done: %+v", e)
	}
}

func TestReconcileReapsDoneAndBumpsOnStaleTransition(t *testing.T) {
	s, c, _ := newStore(t)
	reg(t, s, model.Entity{ID: "a", Kind: "shell", PID: 5, Track: "1", Branch: "b", Alias: "x", Model: "m", Effort: "e"})
	reg(t, s, model.Entity{ID: "b", Kind: "shell", Track: "1", Branch: "b", Alias: "x", Model: "m", Effort: "e"})
	if _, err := s.Apply(model.Event{Type: model.EvUnregister, ID: "b"}); err != nil {
		t.Fatal(err)
	}
	seq0, _ := s.Seq()
	ch, reaped, err := s.Reconcile()
	if err != nil || ch || len(reaped) != 0 {
		t.Fatalf("nothing to do: ch=%v reaped=%v err=%v", ch, reaped, err)
	}
	if seq1, _ := s.Seq(); seq1 != seq0 {
		t.Fatal("idle reconcile must not bump seq")
	}
	c.Add(3 * time.Minute) // a becomes stale
	ch, reaped, err = s.Reconcile()
	if err != nil || !ch || len(reaped) != 0 {
		t.Fatalf("stale transition: ch=%v reaped=%v err=%v", ch, reaped, err)
	}
	if seq2, _ := s.Seq(); seq2 <= seq0 {
		t.Fatal("stale transition must bump seq so watchers see it")
	}
	c.Add(10 * time.Minute) // b past retention
	_, reaped, err = s.Reconcile()
	if err != nil || len(reaped) != 1 || reaped[0] != "b" {
		t.Fatalf("reaped=%v err=%v", reaped, err)
	}
	snap, _ := s.Snapshot()
	if len(snap.Entities) != 1 || snap.Entities[0].ID != "a" {
		t.Fatalf("after reap: %+v", snap.Entities)
	}
}

func TestPartialLastLineTolerated(t *testing.T) {
	s, _, _ := newStore(t)
	reg(t, s, model.Entity{ID: "a", Kind: "shell"})
	f, _ := os.OpenFile(filepath.Join(s.Dir(), "events.jsonl"), os.O_APPEND|os.O_WRONLY, 0o600)
	f.WriteString(`{"seq":2,"type":"regis`) // torn write, no newline
	f.Close()
	if err := s.Verify(); err != nil {
		t.Fatalf("torn tail must be tolerated by Verify: %v", err)
	}
	reg(t, s, model.Entity{ID: "b", Kind: "shell"})
	evs, err := s.EventsSince(0)
	if err != nil || len(evs) != 2 || evs[1].Seq != 2 {
		t.Fatalf("events=%+v err=%v", evs, err)
	}
	if err := s.Verify(); err != nil {
		t.Fatalf("verify after recovery: %v", err)
	}
}

func TestMidFileCorruptionFailsVerify(t *testing.T) {
	s, _, _ := newStore(t)
	reg(t, s, model.Entity{ID: "a", Kind: "shell"})
	reg(t, s, model.Entity{ID: "b", Kind: "shell"})
	p := filepath.Join(s.Dir(), "events.jsonl")
	b, _ := os.ReadFile(p)
	b = bytes.Replace(b, []byte(`"seq":1`), []byte(`"seq":1,"type":{`), 1) // break the first line
	os.WriteFile(p, b, 0o600)
	if err := s.Verify(); err == nil {
		t.Fatal("mid-file corruption must fail Verify")
	}
}

func TestCorruptFoldRebuiltFromLog(t *testing.T) {
	s, _, _ := newStore(t)
	reg(t, s, model.Entity{ID: "a", Kind: "shell", Track: "1", Branch: "b", Alias: "x", Model: "m", Effort: "e"})
	switchAlias(t, s, "claude5", "opus", "low")
	fp := filepath.Join(s.Dir(), "fold.json")
	b, _ := os.ReadFile(fp)
	os.WriteFile(fp, b[:len(b)/2], 0o600)
	snap, err := s.Snapshot()
	if err != nil || snap.Active.Alias != "claude5" || len(snap.Entities) != 1 {
		t.Fatalf("rebuild failed: %+v err=%v", snap, err)
	}
	reg(t, s, model.Entity{ID: "c", Kind: "shell"})
	if err := s.Verify(); err != nil {
		t.Fatalf("verify: %v", err)
	}
}

func TestCrashBetweenAppendAndFold(t *testing.T) {
	s, _, _ := newStore(t)
	reg(t, s, model.Entity{ID: "a", Kind: "shell", Track: "1", Branch: "b", Alias: "x", Model: "m", Effort: "e"})
	// simulate: event 2 durably appended, process killed before fold/snapshot/seq
	e := model.Entity{ID: "late", Kind: "shell", Track: "1", Branch: "b", Alias: "x", Model: "m", Effort: "e"}
	ev := model.Event{Seq: 2, TS: s.opts.Now(), Type: model.EvRegister, Entity: &e}
	line, _ := json.Marshal(ev)
	f, _ := os.OpenFile(filepath.Join(s.Dir(), "events.jsonl"), os.O_APPEND|os.O_WRONLY, 0o600)
	f.Write(append(line, '\n'))
	f.Close()
	if got := get(t, s, "late"); got.ID != "late" {
		t.Fatal("reader must catch up tail")
	}
	out, err := s.Apply(model.Event{Type: model.EvHeartbeat, ID: "late"})
	if err != nil || out.Seq != 3 {
		t.Fatalf("next seq must continue from log: %+v err=%v", out, err)
	}
	if err := s.Verify(); err != nil {
		t.Fatal(err)
	}
}

func TestTruncatedSnapshotDetectedAndHealed(t *testing.T) {
	s, _, _ := newStore(t)
	reg(t, s, model.Entity{ID: "a", Kind: "shell"})
	sp := filepath.Join(s.Dir(), "snapshot.json")
	b, _ := os.ReadFile(sp)
	os.WriteFile(sp, b[:len(b)/3], 0o600)
	if err := s.Verify(); err == nil {
		t.Fatal("truncated snapshot must fail Verify")
	}
	reg(t, s, model.Entity{ID: "b", Kind: "shell"})
	if err := s.Verify(); err != nil {
		t.Fatalf("next write must heal: %v", err)
	}
}

func TestWriteAtomicTornTempLeavesOriginalIntact(t *testing.T) {
	p := filepath.Join(t.TempDir(), "snapshot.json")
	if err := WriteAtomic(p, []byte(`{"v":"original-complete-content"}`)); err != nil {
		t.Fatal(err)
	}
	err := writeAtomic(p, []byte(`{"v":"new-content-that-gets-torn-halfway"}`), 0o600, true)
	if err == nil {
		t.Fatal("simulated torn write must report an error")
	}
	got, _ := os.ReadFile(p)
	if string(got) != `{"v":"original-complete-content"}` {
		t.Fatalf("destination corrupted by torn write: %q", got)
	}
	var v map[string]string
	if json.Unmarshal(got, &v) != nil {
		t.Fatal("destination no longer valid JSON")
	}
	if err := WriteAtomic(p, []byte(`{"v":"next"}`)); err != nil {
		t.Fatal(err)
	}
	got, _ = os.ReadFile(p)
	if string(got) != `{"v":"next"}` {
		t.Fatalf("got %q", got)
	}
}

func TestConcurrentWritersAcrossStores(t *testing.T) {
	dir := t.TempDir()
	const workers, per = 8, 25
	var wg sync.WaitGroup
	errs := make(chan error, workers*per)
	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func(w int) {
			defer wg.Done()
			s, err := Open(Options{Dir: dir, Pids: fakePids{}, TTL: time.Hour, LockTimeout: time.Minute})
			if err != nil {
				errs <- err
				return
			}
			for i := 0; i < per; i++ {
				e := model.Entity{ID: fmt.Sprintf("w%d-%d", w, i), Kind: "command", Track: "1", Branch: "b", Alias: "a", Model: "m", Effort: "e"}
				if _, err := s.Apply(model.Event{Type: model.EvRegister, Entity: &e}); err != nil {
					errs <- err
				}
			}
		}(w)
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Fatal(err)
	}
	s, _ := Open(Options{Dir: dir, Pids: fakePids{}, TTL: time.Hour})
	snap, err := s.Snapshot()
	if err != nil || len(snap.Entities) != workers*per || snap.Seq != workers*per {
		t.Fatalf("entities=%d seq=%d err=%v", len(snap.Entities), snap.Seq, err)
	}
	evs, _ := s.EventsSince(0)
	seen := map[uint64]bool{}
	for _, ev := range evs {
		if seen[ev.Seq] {
			t.Fatalf("duplicate seq %d", ev.Seq)
		}
		seen[ev.Seq] = true
	}
	if err := s.Verify(); err != nil {
		t.Fatal(err)
	}
}

func TestUpdatePatchAndFollowToggle(t *testing.T) {
	s, _, _ := newStore(t)
	switchAlias(t, s, "claude1", "opus", "high")
	reg(t, s, model.Entity{ID: "a", Kind: "agent", Track: "1", Branch: "b", FollowActive: true})
	if _, err := s.Apply(model.Event{Type: model.EvUpdate, ID: "a", Patch: map[string]string{
		"follow_active": "false", "alias": "claude6", "model": "haiku", "effort": "low", "state": "idle", "pid": "77"}}); err != nil {
		t.Fatal(err)
	}
	e := get(t, s, "a")
	if e.Label != "(T1/b - claude6 - haiku - low)" || e.State != "idle" || e.PID != 77 || e.FollowActive {
		t.Fatalf("%+v", e)
	}
}
