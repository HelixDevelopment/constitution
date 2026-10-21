package state

// Second-review fixes: finding 7 (bounded stale sweeper), finding 9 (patch ids
// validated at the store AND at the fold), finding 12 (negative pids).

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
)

// Finding 9 / mutant R1: the FOLD itself rejects an invalid parent_id /
// session_id in an update patch (the store's prepare() is not the only guard:
// a replayed legacy log is folded without prepare()).
func TestFoldRejectsInvalidPatchIDs(t *testing.T) {
	for _, k := range []string{"parent_id", "session_id"} {
		for _, v := range []string{"a b", "ü", "id\x1b[2J", strings.Repeat("a", 161)} {
			r := NewRaw()
			if err := r.Apply(model.Event{Seq: 1, Type: model.EvRegister, Entity: &model.Entity{ID: "e", Kind: "shell"}}); err != nil {
				t.Fatal(err)
			}
			if err := r.Apply(model.Event{Seq: 2, Type: model.EvUpdate, ID: "e", Patch: map[string]string{k: v}}); err == nil {
				t.Fatalf("fold accepted %s=%q", k, v)
			}
			if got := r.Entities["e"]; got.ParentID != "" || got.SessionID != "" {
				t.Fatalf("fold mutated the entity on a rejected patch: %+v", got)
			}
		}
	}
}

// Finding 9: the store's prepare() rejects (never passes through) an invalid
// parent_id / session_id in an update patch, and nothing is logged for it.
func TestStoreRejectsInvalidPatchIDs(t *testing.T) {
	s, _, _ := newStore(t)
	reg(t, s, model.Entity{ID: "e", Kind: "shell"})
	seq := s.PeekSeq()
	for _, k := range []string{"parent_id", "session_id"} {
		if _, err := s.Apply(model.Event{Type: model.EvUpdate, ID: "e", Patch: map[string]string{k: "bad id"}}); err == nil ||
			!strings.Contains(err.Error(), "update: invalid "+k) { // prepare() message, not the fold's
			t.Fatalf("store accepted %s with a space (err=%v)", k, err)
		}
	}
	if s.PeekSeq() != seq || strings.Contains(readFile(t, s.p("events.jsonl")), "bad id") {
		t.Fatal("a rejected patch was sequenced or logged")
	}
}

// Finding 12: a negative or out-of-range pid is rejected at the store.
func TestStoreRejectsBadPids(t *testing.T) {
	s, _, _ := newStore(t)
	for _, pid := range []int{-1, -2147483648, MaxPID + 1} {
		e := model.Entity{ID: fmt.Sprintf("p%d", -pid), Kind: "shell", PID: pid}
		if _, err := s.Apply(model.Event{Type: model.EvRegister, Entity: &e}); err == nil {
			t.Fatalf("register accepted pid %d", pid)
		}
	}
	reg(t, s, model.Entity{ID: "ok", Kind: "shell", PID: 42})
	for _, v := range []string{"-1", "-99", fmt.Sprint(MaxPID + 1)} {
		if _, err := s.Apply(model.Event{Type: model.EvUpdate, ID: "ok", Patch: map[string]string{"pid": v}}); err == nil {
			t.Fatalf("update accepted pid %q", v)
		}
	}
	if got := get(t, s, "ok").PID; got != 42 {
		t.Fatalf("pid changed to %d by a rejected patch", got)
	}
}

func ids(t *testing.T, s *Store) map[string]bool {
	t.Helper()
	snap, err := s.Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	m := map[string]bool{}
	for _, e := range snap.Entities {
		m[e.ID] = true
	}
	return m
}

// Finding 7: entities whose LOCAL process is provably gone and that have not
// been updated for longer than SweepAfter are removed by the next write; live,
// pid-less, remote and recently-updated ones are never touched.
func TestStaleSweeperRemovesOnlyProvablyDeadOldEntities(t *testing.T) {
	s, c, p := newStore(t)
	p[10] = true // alive
	reg(t, s, model.Entity{ID: "dead-old", Kind: "session", PID: 20, Host: "h1"})
	reg(t, s, model.Entity{ID: "alive-old", Kind: "session", PID: 10, Host: "h1"})
	reg(t, s, model.Entity{ID: "pidless-old", Kind: "shell", Host: "h1"})
	reg(t, s, model.Entity{ID: "remote-old", Kind: "session", PID: 30, Host: "other"})
	c.Add(DefaultSweepAfter + time.Second)
	reg(t, s, model.Entity{ID: "dead-young", Kind: "agent", PID: 21, Host: "h1"})
	got := ids(t, s)
	if got["dead-old"] {
		t.Fatal("a provably-dead entity older than SweepAfter survived a write")
	}
	for _, id := range []string{"alive-old", "pidless-old", "remote-old", "dead-young"} {
		if !got[id] {
			t.Fatalf("sweeper removed %s (only provably-dead entities older than SweepAfter may go)", id)
		}
	}
	if err := s.Verify(); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(readFile(t, s.p("events.jsonl")), `"type":"reap","id":"dead-old"`) {
		t.Fatal("sweep is not a logged reap event (consumers could not see it)")
	}
}

// Finding 7: SweepAfter < 0 disables the sweeper; the env knob parses.
func TestStaleSweeperDisabledAndEnv(t *testing.T) {
	c := &clock{t: time.Date(2026, 10, 12, 10, 0, 0, 0, time.UTC)}
	s, err := Open(Options{Dir: t.TempDir(), Now: c.Now, Pids: fakePids{}, LocalHost: "h1", SweepAfter: -1})
	if err != nil {
		t.Fatal(err)
	}
	reg(t, s, model.Entity{ID: "dead", Kind: "session", PID: 20, Host: "h1"})
	c.Add(24 * time.Hour)
	reg(t, s, model.Entity{ID: "other", Kind: "shell"})
	if !ids(t, s)["dead"] {
		t.Fatal("disabled sweeper removed an entity")
	}
	for v, want := range map[string]time.Duration{"off": -1, "90s": 90 * time.Second, "600": 600 * time.Second} {
		t.Setenv("LABEL_SYNC_STALE_SWEEP", v)
		if got := OptionsFromEnv().SweepAfter; got != want {
			t.Fatalf("LABEL_SYNC_STALE_SWEEP=%q -> %v, want %v", v, got, want)
		}
	}
}

// Finding 7: one transaction sweeps at most SweepBatch entities (bounded lock
// hold); repeated writes converge; compaction in between keeps the state
// consistent (base+tail == state, Verify clean).
func TestStaleSweeperIsBoundedAndCompactionAware(t *testing.T) {
	c := &clock{t: time.Date(2026, 10, 12, 10, 0, 0, 0, time.UTC)}
	s, err := Open(Options{Dir: t.TempDir(), Now: c.Now, Pids: fakePids{}, LocalHost: "h1",
		CompactEvents: 40, KeepTail: 8, SweepBatch: 7})
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 30; i++ {
		reg(t, s, model.Entity{ID: fmt.Sprintf("d%02d", i), Kind: "shell", PID: 1000 + i, Host: "h1"})
	}
	c.Add(DefaultSweepAfter + time.Second)
	reg(t, s, model.Entity{ID: "w0", Kind: "shell"})
	if n := len(ids(t, s)); n != 31-7 {
		t.Fatalf("after one write %d entities remain, want %d (batch of 7)", n, 31-7)
	}
	for i := 0; i < 10 && len(ids(t, s)) > 1; i++ {
		if _, err := s.Apply(model.Event{Type: model.EvHeartbeat, ID: "w0"}); err != nil {
			t.Fatal(err)
		}
	}
	if got := ids(t, s); len(got) != 1 || !got["w0"] {
		t.Fatalf("sweeper did not converge: %v", got)
	}
	if err := s.Verify(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(s.p("base.json")); err != nil {
		t.Fatalf("fixture did not exercise compaction: %v", err)
	}
	// a fresh handle (full replay from base+tail) sees the same state
	s2, err := Open(Options{Dir: s.Dir(), Now: c.Now, Pids: fakePids{}, LocalHost: "h1", SweepAfter: -1})
	if err != nil {
		t.Fatal(err)
	}
	if got := ids(t, s2); len(got) != 1 || !got["w0"] {
		t.Fatalf("replayed state differs: %v", got)
	}
}

// Finding 7 performance assertion: with 2000 kill -9 leftovers (written as a
// log, the way they accumulate) the write cost returns to the small-store
// level once swept, and the snapshot shrinks back. The latency bound is
// relative (post-sweep median <= 3x the empty-store median + 15 ms) so a
// loaded host does not flip it; the snapshot size bound is exact.
func TestStaleSweeperRestoresWriteCost(t *testing.T) {
	c := &clock{t: time.Date(2026, 10, 12, 10, 0, 0, 0, time.UTC)}
	open := func(dir string, sweep time.Duration) *Store {
		s, err := Open(Options{Dir: dir, Now: c.Now, Pids: fakePids{}, LocalHost: "h1", SweepAfter: sweep, SweepBatch: 4096})
		if err != nil {
			t.Fatal(err)
		}
		return s
	}
	medianWrite := func(s *Store, n int) time.Duration {
		var d []time.Duration
		for i := 0; i < n; i++ {
			t0 := time.Now()
			if _, err := s.Apply(model.Event{Type: model.EvAliasSwitch, Active: &model.Active{Alias: fmt.Sprint("c", i)}}); err != nil {
				t.Fatal(err)
			}
			d = append(d, time.Since(t0))
		}
		return median(d)
	}
	base := medianWrite(open(t.TempDir(), -1), 7)
	dir := t.TempDir()
	var b strings.Builder
	for i := 0; i < 2000; i++ {
		e := model.Entity{ID: fmt.Sprintf("leftover-%04d", i), Kind: "session", PID: 50000 + i, Host: "h1", State: "running",
			Cwd: "/home/user/Projects/some/where", Track: "3", Branch: "feature/x", Alias: "claude2", Model: "opus", Effort: "xhigh",
			StartedAt: c.Now(), UpdatedAt: c.Now()}
		line, _ := json.Marshal(model.Event{Seq: uint64(i + 1), TS: c.Now(), Type: model.EvRegister, Entity: &e})
		b.Write(line)
		b.WriteByte('\n')
	}
	writeFile(t, dir+"/events.jsonl", b.String())
	full := medianWrite(open(dir, -1), 3)
	big := len(readFile(t, dir+"/snapshot.json"))
	c.Add(DefaultSweepAfter + time.Second)
	s := open(dir, 0)
	t0 := time.Now()
	if _, err := s.Apply(model.Event{Type: model.EvAliasSwitch, Active: &model.Active{Alias: "sweep"}}); err != nil {
		t.Fatal(err)
	}
	sweep := time.Since(t0)
	after := medianWrite(s, 7)
	small := len(readFile(t, dir+"/snapshot.json"))
	t.Logf("empty-store write %v; 2000 leftovers: write %v, snapshot %d B; sweeping write %v; post-sweep write %v, snapshot %d B",
		base, full, big, sweep, after, small)
	if small > 1024 {
		t.Fatalf("snapshot still %d B after the sweep (leftovers not removed)", small)
	}
	if after > 3*base+15*time.Millisecond {
		t.Fatalf("post-sweep write median %v vs empty-store %v: write cost not restored", after, base)
	}
	if sweep > 5*time.Second {
		t.Fatalf("one sweeping write took %v (must stay bounded)", sweep)
	}
	if err := s.Verify(); err != nil {
		t.Fatal(err)
	}
}
