package state

// Tests for the DERIVED binding rule (CONTRACT.md §4): an entity's
// alias/model/effort is resolved at RENDER time — its own values if pinned,
// else its nearest ancestor's binding resolved the same way, else (root only)
// the active context. Nothing is copied at write time.

import (
	"fmt"
	"math/rand"
	"strings"
	"testing"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
)

func aliasOf(t *testing.T, s *Store, id string) string {
	t.Helper()
	return get(t, s, id).Alias
}

// Review finding 1(a): a child registered AFTER a pinned session must show the
// SESSION's alias, never the active one, across switches.
func TestChildRegisteredAfterPinnedSessionFollowsSession(t *testing.T) {
	s, _, _ := newStore(t)
	switchAlias(t, s, "claude1", "opus", "high")
	reg(t, s, model.Entity{ID: "S", Kind: "session", SessionID: "S1", Track: "1", Branch: "main", Alias: "claude2", Model: "sonnet", Effort: "xhigh"})
	reg(t, s, model.Entity{ID: "A", Kind: "agent", SessionID: "S1", ParentID: "S", FollowActive: true})
	if a := aliasOf(t, s, "A"); a != "claude2" {
		t.Fatalf("child of pinned session shows %q, want claude2", a)
	}
	switchAlias(t, s, "claude3", "haiku", "low")
	if l := get(t, s, "A").Label; l != "(T1/main - claude2 - sonnet - xhigh)" {
		t.Fatalf("after operator switch child label %q", l)
	}
	// a child linked ONLY by session_id (no parent_id) also binds to its session
	reg(t, s, model.Entity{ID: "B", Kind: "agent", SessionID: "S1", FollowActive: true})
	if a := aliasOf(t, s, "B"); a != "claude2" {
		t.Fatalf("session_id-linked child shows %q, want claude2", a)
	}
}

// Review finding 1(b): children are never left pinned by a past republish —
// a session re-registered to FOLLOW takes its whole subtree with it.
func TestSessionReRegisteredFollowingUnpinsChildren(t *testing.T) {
	s, _, _ := newStore(t)
	switchAlias(t, s, "claude1", "opus", "high")
	reg(t, s, model.Entity{ID: "sub", Kind: "subagent", SessionID: "S1", Track: "1", Branch: "main", FollowActive: true})
	reg(t, s, model.Entity{ID: "S", Kind: "session", SessionID: "S1", Track: "1", Branch: "main", Alias: "claude2", Model: "sonnet", Effort: "xhigh"})
	if a := aliasOf(t, s, "sub"); a != "claude2" {
		t.Fatalf("pinned session subtree shows %q", a)
	}
	reg(t, s, model.Entity{ID: "S", Kind: "session", SessionID: "S1", Track: "1", Branch: "main", FollowActive: true})
	switchAlias(t, s, "claude4", "fable", "max")
	if l := get(t, s, "sub").Label; l != "(T1/main - claude4 - fable - max)" {
		t.Fatalf("subagent stuck after session unpinned: %q", l)
	}
	if l := get(t, s, "S").Label; l != "(T1/main - claude4 - fable - max)" {
		t.Fatalf("session: %q", l)
	}
}

// A session resumed under a DIFFERENT alias rebinds its subtree immediately,
// with no write to any child.
func TestResumeUnderDifferentAliasRebindsSubtree(t *testing.T) {
	s, _, _ := newStore(t)
	reg(t, s, model.Entity{ID: "S", Kind: "session", SessionID: "S1", Track: "2", Branch: "b", Alias: "claude2", Model: "opus", Effort: "high"})
	reg(t, s, model.Entity{ID: "c", Kind: "agent", ParentID: "S", FollowActive: true})
	reg(t, s, model.Entity{ID: "g", Kind: "command", ParentID: "c", FollowActive: true})
	before, _ := s.EventsSince(0)
	reg(t, s, model.Entity{ID: "S", Kind: "session", SessionID: "S1", Track: "2", Branch: "b", Alias: "claude5", Model: "sonnet", Effort: "low"})
	for _, id := range []string{"S", "c", "g"} {
		if l := get(t, s, id).Label; l != "(T2/b - claude5 - sonnet - low)" {
			t.Fatalf("%s after resume: %q", id, l)
		}
	}
	after, _ := s.EventsSince(0)
	if len(after) != len(before)+1 {
		t.Fatalf("resume must be ONE event (derived, not copied): %d -> %d", len(before), len(after))
	}
	// declared state of the children is untouched (no copy-on-republish)
	r, _ := s.load()
	if r.Entities["c"].Alias != "" || !r.Entities["c"].FollowActive || r.Entities["g"].Alias != "" {
		t.Fatalf("children were rewritten: c=%+v g=%+v", r.Entities["c"], r.Entities["g"])
	}
}

// Two terminals on two aliases never cross-contaminate, through ANY sequence
// of alias switches and child registrations (randomised, seeded, replayable).
func TestTwoPinnedSessionsNeverCrossContaminate(t *testing.T) {
	for seed := int64(1); seed <= 5; seed++ {
		t.Run(fmt.Sprintf("seed%d", seed), func(t *testing.T) {
			s, c, _ := newStore(t)
			rnd := rand.New(rand.NewSource(seed))
			reg(t, s, model.Entity{ID: "SA", Kind: "session", SessionID: "A", Alias: "claude1", Model: "opus", Effort: "high"})
			reg(t, s, model.Entity{ID: "SB", Kind: "session", SessionID: "B", Alias: "claude2", Model: "sonnet", Effort: "low"})
			want := map[string]string{"SA": "claude1", "SB": "claude2"}
			nodes := map[string][]string{"A": {"SA"}, "B": {"SB"}}
			for i := 0; i < 60; i++ {
				c.Add(time.Second)
				switch rnd.Intn(3) {
				case 0:
					switchAlias(t, s, fmt.Sprintf("claude%d", 3+rnd.Intn(5)), "m", "e")
				default:
					grp := []string{"A", "B"}[rnd.Intn(2)]
					par := nodes[grp][rnd.Intn(len(nodes[grp]))]
					id := fmt.Sprintf("%s-n%d", grp, i)
					e := model.Entity{ID: id, Kind: "agent", ParentID: par, FollowActive: rnd.Intn(2) == 0}
					if rnd.Intn(3) == 0 {
						e.ParentID, e.SessionID = "", grp // session_id-only link
					}
					reg(t, s, e)
					nodes[grp] = append(nodes[grp], id)
					want[id] = map[string]string{"A": "claude1", "B": "claude2"}[grp]
				}
				snap, err := s.Snapshot()
				if err != nil {
					t.Fatal(err)
				}
				got := map[string]string{}
				for _, e := range snap.Entities {
					got[e.ID] = e.Alias
				}
				for id, w := range want {
					if got[id] != w {
						t.Fatalf("step %d: %s shows %q, want %q", i, id, got[id], w)
					}
				}
			}
		})
	}
}

// Deep nesting: binding AND track/branch inherit through several unbound
// levels (kills depth-1 / depth-2 truncation mutants).
func TestDeepNestingInheritsBindingAndPlace(t *testing.T) {
	s, _, _ := newStore(t)
	switchAlias(t, s, "claude9", "x", "y")
	reg(t, s, model.Entity{ID: "n0", Kind: "session", SessionID: "D", Track: "7", Branch: "deep", Alias: "claude3", Model: "opus", Effort: "max"})
	prev := "n0"
	for i := 1; i <= 6; i++ {
		id := fmt.Sprintf("n%d", i)
		reg(t, s, model.Entity{ID: id, Kind: "agent", ParentID: prev, FollowActive: true})
		prev = id
	}
	for i := 1; i <= 6; i++ {
		if l := get(t, s, fmt.Sprintf("n%d", i)).Label; l != "(T7/deep - claude3 - opus - max)" {
			t.Fatalf("depth %d: %q", i, l)
		}
	}
}

// A FOLLOWING ancestor's stale stored alias must never leak to a child: the
// child resolves through the ancestor to the ACTIVE context.
func TestInheritingFromFollowingAncestorUsesActive(t *testing.T) {
	s, _, _ := newStore(t)
	switchAlias(t, s, "claude1", "opus", "high")
	reg(t, s, model.Entity{ID: "S", Kind: "session", SessionID: "F", Track: "1", Branch: "b", Alias: "stale-own", FollowActive: true})
	reg(t, s, model.Entity{ID: "k", Kind: "agent", ParentID: "S", FollowActive: false})
	if a := aliasOf(t, s, "k"); a != "claude1" {
		t.Fatalf("child of following session shows %q, want active claude1", a)
	}
	switchAlias(t, s, "claude2", "sonnet", "low")
	if l := get(t, s, "k").Label; l != "(T1/b - claude2 - sonnet - low)" {
		t.Fatalf("after switch: %q", l)
	}
}

// Pinned child under a following session keeps its OWN binding.
func TestPinnedChildKeepsOwnBinding(t *testing.T) {
	s, _, _ := newStore(t)
	switchAlias(t, s, "claude1", "opus", "high")
	reg(t, s, model.Entity{ID: "S", Kind: "session", SessionID: "P", FollowActive: true})
	reg(t, s, model.Entity{ID: "pc", Kind: "agent", ParentID: "S", Alias: "prov-x", Model: "deepseek", Effort: "low"})
	switchAlias(t, s, "claude2", "sonnet", "low")
	if a := aliasOf(t, s, "pc"); a != "prov-x" {
		t.Fatalf("pinned child shows %q", a)
	}
}

// Review mutant: TTL ">=" instead of ">" — an entity EXACTLY at the TTL is not stale.
func TestStaleBoundaryExactlyAtTTLIsNotStale(t *testing.T) {
	s, c, _ := newStore(t)
	reg(t, s, model.Entity{ID: "x", Kind: "flow"})
	c.Add(2 * time.Minute) // == TTL
	if e := get(t, s, "x"); e.Stale {
		t.Fatalf("age == TTL must not be stale: %+v", e)
	}
	c.Add(time.Nanosecond)
	if e := get(t, s, "x"); !e.Stale {
		t.Fatalf("age > TTL must be stale: %+v", e)
	}
}

// Review mutant: started_at must survive re-registration.
func TestStartedAtKeptOnReRegister(t *testing.T) {
	s, c, _ := newStore(t)
	reg(t, s, model.Entity{ID: "x", Kind: "shell"})
	t0 := get(t, s, "x").StartedAt
	c.Add(time.Hour)
	reg(t, s, model.Entity{ID: "x", Kind: "shell", Branch: "again"})
	if got := get(t, s, "x").StartedAt; !got.Equal(t0) {
		t.Fatalf("started_at changed on re-register: %v -> %v", t0, got)
	}
}

// Review mutant: heartbeat must revive a DECLARED unknown state.
func TestHeartbeatRevivesDeclaredUnknown(t *testing.T) {
	s, _, _ := newStore(t)
	reg(t, s, model.Entity{ID: "x", Kind: "shell", State: "unknown"})
	if _, err := s.Apply(model.Event{Type: model.EvHeartbeat, ID: "x"}); err != nil {
		t.Fatal(err)
	}
	if st := get(t, s, "x").State; st != "running" {
		t.Fatalf("heartbeat left state %q", st)
	}
	// an explicit state in the heartbeat wins
	if _, err := s.Apply(model.Event{Type: model.EvHeartbeat, ID: "x", Patch: map[string]string{"state": "idle"}}); err != nil {
		t.Fatal(err)
	}
	if st := get(t, s, "x").State; st != "idle" {
		t.Fatalf("explicit heartbeat state lost: %q", st)
	}
}

// Review mutants: Verify must catch a fold.json that disagrees with the log, a
// seq file ahead of the log, and a snapshot ahead of the log.
func TestVerifyCatchesFoldMismatchSeqAheadSnapshotAhead(t *testing.T) {
	mk := func(t *testing.T) *Store {
		s, _, _ := newStore(t)
		reg(t, s, model.Entity{ID: "a", Kind: "shell", Alias: "x"})
		reg(t, s, model.Entity{ID: "b", Kind: "shell"})
		if err := s.Verify(); err != nil {
			t.Fatalf("clean verify: %v", err)
		}
		return s
	}
	t.Run("fold mismatch", func(t *testing.T) {
		s := mk(t)
		p := s.p("fold.json")
		b := readFile(t, p)
		b = strings.Replace(b, `"alias":"x"`, `"alias":"tampered"`, 1)
		writeFile(t, p, b)
		if err := s.Verify(); err == nil || !strings.Contains(err.Error(), "fold.json") {
			t.Fatalf("fold mismatch not reported: %v", err)
		}
	})
	t.Run("seq ahead", func(t *testing.T) {
		s := mk(t)
		writeFile(t, s.p("seq"), "3\n")
		if err := s.Verify(); err == nil || !strings.Contains(err.Error(), "seq file") {
			t.Fatalf("seq-ahead (by ONE) not reported: %v", err)
		}
	})
	t.Run("snapshot ahead", func(t *testing.T) {
		s := mk(t)
		p := s.p("snapshot.json")
		b := readFile(t, p)
		b = strings.Replace(b, `"seq": 2`, `"seq": 3`, 1)
		writeFile(t, p, b)
		if err := s.Verify(); err == nil || !strings.Contains(err.Error(), "snapshot.json") {
			t.Fatalf("snapshot-ahead (by ONE) not reported: %v", err)
		}
	})
}
