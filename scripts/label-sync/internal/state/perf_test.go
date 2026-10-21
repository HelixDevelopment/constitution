package state

// Performance measurement (review finding 5). Opt-in: LABEL_SYNC_PERF=1.
// LABEL_SYNC_PERF_ASSERT=1 additionally fails when a steady-state median
// exceeds 20 ms. The history generator matches the reviewer's harness: 40
// long-lived shells + command churn (register/unregister/reap), written as an
// UNCOMPACTED legacy log, so the first write also measures the one-time
// migration (compaction) cost.

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"testing"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
)

func legacyHistory(t *testing.T, dir string, n int) {
	t.Helper()
	f, err := os.Create(filepath.Join(dir, "events.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	w := bufio.NewWriterSize(f, 1<<20)
	ts := time.Now().UTC().Add(-time.Hour)
	seq := uint64(0)
	emit := func(ev model.Event) {
		seq++
		ev.Seq, ev.TS = seq, ts
		b, _ := json.Marshal(ev)
		w.Write(append(b, '\n'))
	}
	for i := 0; i < 40; i++ {
		e := model.Entity{ID: fmt.Sprintf("shell-host-%d-1760000000", 1000+i), Kind: "shell", Host: "host",
			Cwd: "/home/user/Projects/some/where", Track: "3", Branch: "feature/label-sync", Alias: "claude2", Model: "opus",
			Effort: "xhigh", Source: "shell-integration"}
		emit(model.Event{Type: model.EvRegister, Entity: &e})
	}
	for i := 0; int(seq) < n; i++ {
		id := fmt.Sprintf("shell-host-%d-1760000000-c%d", 1000+i%40, i)
		e := model.Entity{ID: id, Kind: "command", ParentID: fmt.Sprintf("shell-host-%d-1760000000", 1000+i%40),
			Host: "host", Cwd: "/home/user/Projects/some/where", Source: "shell-integration:argv0=git:h=0123456789ab", FollowActive: true}
		emit(model.Event{Type: model.EvRegister, Entity: &e})
		emit(model.Event{Type: model.EvUnregister, ID: id})
		emit(model.Event{Type: model.EvReap, ID: id})
	}
	w.Flush()
	f.Close()
}

func median(d []time.Duration) time.Duration {
	sort.Slice(d, func(i, j int) bool { return d[i] < d[j] })
	return d[len(d)/2]
}

func TestPerfLogGrowth(t *testing.T) {
	if os.Getenv("LABEL_SYNC_PERF") != "1" {
		t.Skip("set LABEL_SYNC_PERF=1")
	}
	for _, n := range []int{10000, 100000} {
		dir := t.TempDir()
		legacyHistory(t, dir, n)
		s, err := Open(Options{Dir: dir, TTL: time.Hour, Pids: fakePids{}})
		if err != nil {
			t.Fatal(err)
		}
		t0 := time.Now()
		if _, err := s.Apply(model.Event{Type: model.EvHeartbeat, ID: "shell-host-1000-1760000000"}); err != nil {
			t.Fatal(err)
		}
		migrate := time.Since(t0)
		const k = 21
		var ap, sn, es []time.Duration
		for i := 0; i < k; i++ {
			t0 = time.Now()
			ev, err := s.Apply(model.Event{Type: model.EvHeartbeat, ID: "shell-host-1000-1760000000"})
			if err != nil {
				t.Fatal(err)
			}
			ap = append(ap, time.Since(t0))
			t0 = time.Now()
			if _, err := s.Snapshot(); err != nil {
				t.Fatal(err)
			}
			sn = append(sn, time.Since(t0))
			t0 = time.Now()
			if _, err := s.EventsSince(ev.Seq - 1); err != nil {
				t.Fatal(err)
			}
			es = append(es, time.Since(t0))
		}
		st, _ := os.Stat(filepath.Join(dir, "events.jsonl"))
		sp, _ := os.Stat(filepath.Join(dir, "snapshot.json"))
		t.Logf("PERF logical_events=%d first_write_with_migration=%v write_median=%v read_median=%v events_since_tail_median=%v log_bytes_after=%d snapshot_bytes=%d",
			n, migrate, median(ap), median(sn), median(es), st.Size(), sp.Size())
		if os.Getenv("LABEL_SYNC_PERF_ASSERT") == "1" {
			for name, d := range map[string]time.Duration{"write": median(ap), "read": median(sn), "since": median(es)} {
				if d > 20*time.Millisecond {
					t.Errorf("%d events: %s median %v > 20ms", n, name, d)
				}
			}
		}
		if err := s.Verify(); err != nil {
			t.Fatal(err)
		}
	}
}

// TestPerfBuildStatuslineState builds, in $LABEL_SYNC_PERF_DIR, a state dir
// with 20k historic events (done-and-past-retention command churn) followed by
// one write, for timing render/statusline.sh against it.
func TestPerfBuildStatuslineState(t *testing.T) {
	dir := os.Getenv("LABEL_SYNC_PERF_DIR")
	if dir == "" {
		t.Skip("set LABEL_SYNC_PERF_DIR")
	}
	legacyHistory(t, dir, 20000)
	s, err := Open(Options{Dir: dir, TTL: time.Hour})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.Apply(model.Event{Type: model.EvAliasSwitch, Active: &model.Active{Alias: "claude2", Model: "opus", Effort: "xhigh"}}); err != nil {
		t.Fatal(err)
	}
	sess := model.Entity{ID: "session:SID-1", Kind: model.KindSession, SessionID: "SID-1", Track: "3", Branch: "main", Alias: "claude2", Model: "opus", Effort: "xhigh"}
	if _, err := s.Apply(model.Event{Type: model.EvRegister, Entity: &sess}); err != nil {
		t.Fatal(err)
	}
	sp, _ := os.Stat(filepath.Join(dir, "snapshot.json"))
	t.Logf("PERF statusline_state events=20000 snapshot_bytes=%d", sp.Size())
}
