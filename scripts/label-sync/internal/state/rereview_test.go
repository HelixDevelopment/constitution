package state

// Re-review (third review) finding 2: a process that is alive in ANOTHER PID
// namespace (a container sharing the state dir) is not provably dead to a
// writer outside that namespace — its pid means nothing there.

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
)

// nsPids is a fake pid table that also reports the writer's own PID namespace.
type nsPids struct {
	fakePids
	ns string
}

func (n nsPids) NS() string { return n.ns }

const (
	nsContainer = "pid:[4026532001]"
	nsHost      = "pid:[4026531836]"
)

func openNS(t *testing.T, dir string, c *clock, p fakePids, ns string) *Store {
	t.Helper()
	s, err := Open(Options{Dir: dir, Now: c.Now, Pids: nsPids{p, ns}, LocalHost: "h1"})
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestSweeperKeepsEntitiesFromAnotherPIDNamespace(t *testing.T) {
	dir := t.TempDir()
	c := &clock{t: time.Date(2026, 10, 14, 10, 0, 0, 0, time.UTC)}
	inside := openNS(t, dir, c, fakePids{7: true}, nsContainer)
	reg(t, inside, model.Entity{ID: "ct-shell", Kind: "shell", PID: 7, Host: "h1"})
	if !strings.Contains(readFile(t, filepath.Join(dir, "events.jsonl")), `"pid_ns":"`+nsContainer+`"`) {
		t.Fatal("register does not record the registering process's PID namespace")
	}
	c.Add(DefaultSweepAfter + time.Second)
	host := openNS(t, dir, c, fakePids{}, nsHost) // pid 7 is NOT alive in the host's view
	reg(t, host, model.Entity{ID: "host-shell", Kind: "shell", PID: 99, Host: "h1"})
	if !ids(t, host)["ct-shell"] {
		t.Fatal("a writer in another PID namespace swept an entity whose process it cannot see (not provably dead)")
	}
	// control: a writer in the SAME namespace, where pid 7 is gone, sweeps it
	same := openNS(t, dir, c, fakePids{}, nsContainer)
	reg(t, same, model.Entity{ID: "ct-other", Kind: "shell", PID: 8, Host: "h1"})
	if ids(t, same)["ct-shell"] {
		t.Fatal("control: a same-namespace writer must sweep a provably-dead old entity")
	}
}

// An entity recorded without a namespace (older writer) is not provably dead to
// a writer that knows its own namespace: kept, never guessed.
func TestSweeperKeepsEntityWithUnknownNamespace(t *testing.T) {
	dir := t.TempDir()
	c := &clock{t: time.Date(2026, 10, 14, 10, 0, 0, 0, time.UTC)}
	old := openNS(t, dir, c, fakePids{}, "") // cannot read its namespace
	reg(t, old, model.Entity{ID: "legacy", Kind: "shell", PID: 7, Host: "h1"})
	c.Add(DefaultSweepAfter + time.Second)
	w := openNS(t, dir, c, fakePids{}, nsHost)
	reg(t, w, model.Entity{ID: "w", Kind: "shell", PID: 9, Host: "h1"})
	if !ids(t, w)["legacy"] {
		t.Fatal("an entity with no recorded namespace was swept by a namespace-aware writer")
	}
}

// ProcPids reads its namespace from <root>/self/ns/pid (a symlink "pid:[N]").
func TestProcPidsNamespaceFromProc(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "self", "ns"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(nsContainer, filepath.Join(root, "self", "ns", "pid")); err != nil {
		t.Fatal(err)
	}
	n, ok := any(ProcPids{Root: root}).(interface{ NS() string })
	if !ok {
		t.Fatal("ProcPids does not report its PID namespace (no NS method)")
	}
	if got := n.NS(); got != nsContainer {
		t.Fatalf("NS() = %q, want %q", got, nsContainer)
	}
	if got := any(ProcPids{Root: t.TempDir()}).(interface{ NS() string }).NS(); got != "" {
		t.Fatalf("NS() without a readable link = %q, want \"\"", got)
	}
}

// A pid updated by a writer in ANOTHER namespace must not keep the old
// namespace: the fold clears it, so no writer can sweep on a wrong pairing.
func TestPidPatchClearsRecordedNamespace(t *testing.T) {
	dir := t.TempDir()
	c := &clock{t: time.Date(2026, 10, 14, 10, 0, 0, 0, time.UTC)}
	inside := openNS(t, dir, c, fakePids{7: true}, nsContainer)
	reg(t, inside, model.Entity{ID: "e", Kind: "shell", PID: 7, Host: "h1"})
	host := openNS(t, dir, c, fakePids{1234: true}, nsHost)
	if _, err := host.Apply(model.Event{Type: model.EvUpdate, ID: "e", Patch: map[string]string{"pid": "1234"}}); err != nil {
		t.Fatal(err)
	}
	c.Add(DefaultSweepAfter + time.Second)
	again := openNS(t, dir, c, fakePids{}, nsContainer) // pid 1234 means nothing here
	reg(t, again, model.Entity{ID: "w", Kind: "shell", PID: 9, Host: "h1"})
	if !ids(t, again)["e"] {
		t.Fatal("an entity whose pid was set from another namespace was swept on a stale namespace")
	}
}

// ---- re-review 3, finding 1: upgrade path and bounded growth -------------

// preFixEntity is the entity struct of a writer built BEFORE pid_ns existed:
// a pre-fix labelctl decodes fold.json into it and writes it back.
type preFixEntity struct {
	ID           string    `json:"id"`
	Kind         string    `json:"kind"`
	ParentID     string    `json:"parent_id,omitempty"`
	SessionID    string    `json:"session_id,omitempty"`
	PID          int       `json:"pid,omitempty"`
	PIDStart     string    `json:"pid_start,omitempty"`
	Host         string    `json:"host,omitempty"`
	Cwd          string    `json:"cwd,omitempty"`
	FollowActive bool      `json:"follow_active"`
	Source       string    `json:"source,omitempty"`
	StartedAt    time.Time `json:"started_at"`
	UpdatedAt    time.Time `json:"updated_at"`
	State        string    `json:"state"`
}

type preFixRaw struct {
	Seq      uint64                   `json:"seq"`
	Active   model.Active             `json:"active"`
	Entities map[string]*preFixEntity `json:"entities"`
	Index    logIndex                 `json:"index"`
}

func roundTripThroughPreFix(t *testing.T, path string) {
	t.Helper()
	var r preFixRaw
	if err := json.Unmarshal([]byte(readFile(t, path)), &r); err != nil {
		t.Fatal(err)
	}
	b, err := json.Marshal(&r)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, b, 0o600); err != nil {
		t.Fatal(err)
	}
}

// A pre-fix writer re-marshals fold.json without pid_ns; `repair` re-folds
// base.json + events.jsonl and restores it (the events still carry it).
func TestRepairRestoresNamespaceStrippedByPreFixWriter(t *testing.T) {
	dir := t.TempDir()
	c := &clock{t: time.Date(2026, 10, 15, 10, 0, 0, 0, time.UTC)}
	s := openNS(t, dir, c, fakePids{7: true}, nsContainer)
	reg(t, s, model.Entity{ID: "ct-shell", Kind: "shell", PID: 7, Host: "h1"})
	roundTripThroughPreFix(t, filepath.Join(dir, "fold.json"))
	if err := s.Verify(); err == nil || !strings.Contains(err.Error(), "fold.json differs") {
		t.Fatalf("fixture: verify must see the stripped fold (got %v)", err)
	}
	rp, ok := any(s).(interface{ Repair() (int, error) })
	if !ok {
		t.Fatal("Store has no Repair (re-fold base.json+events.jsonl) route")
	}
	if _, err := rp.Repair(); err != nil {
		t.Fatal(err)
	}
	if err := s.Verify(); err != nil {
		t.Fatalf("verify after repair: %v", err)
	}
	if !strings.Contains(readFile(t, filepath.Join(dir, "fold.json")), `"pid_ns":"`+nsContainer+`"`) {
		t.Fatal("repair did not restore pid_ns from the event log")
	}
}

// Fields this version does not know are carried through a read/write cycle
// (forward compatibility for the NEXT field).
func TestEntityCarriesUnknownFields(t *testing.T) {
	in := `{"id":"x","kind":"shell","follow_active":false,"started_at":"0001-01-01T00:00:00Z","updated_at":"0001-01-01T00:00:00Z","state":"","future_field":{"a":1}}`
	var e model.Entity
	if err := json.Unmarshal([]byte(in), &e); err != nil {
		t.Fatal(err)
	}
	out, err := json.Marshal(&e)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(out), `"future_field":{"a":1}`) {
		t.Fatalf("an unknown field was dropped by a read/write cycle: %s", out)
	}
}

// Bounded growth: an entity with NO recorded namespace whose pid is dead in
// this writer's view goes after DefaultSweepUnknownNS; one from ANOTHER
// namespace (liveness unknowable here) after DefaultSweepForeignNS without
// any update. Younger ones stay.
func TestSweeperBoundsUnknownAndForeignNamespaces(t *testing.T) {
	dir := t.TempDir()
	c := &clock{t: time.Date(2026, 10, 15, 10, 0, 0, 0, time.UTC)}
	old := openNS(t, dir, c, fakePids{}, "")
	reg(t, old, model.Entity{ID: "legacy", Kind: "shell", PID: 7, Host: "h1"})
	ct := openNS(t, dir, c, fakePids{8: true}, nsContainer)
	reg(t, ct, model.Entity{ID: "foreign", Kind: "shell", PID: 8, Host: "h1"})
	w := openNS(t, dir, c, fakePids{}, nsHost)
	c.Add(23 * time.Hour)
	reg(t, w, model.Entity{ID: "w1", Kind: "shell", PID: 9, Host: "h1"})
	if got := ids(t, w); !got["legacy"] || !got["foreign"] {
		t.Fatalf("swept too early (23h): %v", got)
	}
	c.Add(2 * time.Hour) // 25h
	reg(t, w, model.Entity{ID: "w2", Kind: "shell", PID: 9, Host: "h1"})
	if got := ids(t, w); got["legacy"] || !got["foreign"] {
		t.Fatalf("after 25h: the dead no-namespace entity must go, the foreign one stay: %v", got)
	}
	c.Add(6 * 24 * time.Hour) // 7d1h
	reg(t, w, model.Entity{ID: "w3", Kind: "shell", PID: 9, Host: "h1"})
	if ids(t, w)["foreign"] {
		t.Fatal("a foreign-namespace entity not updated for > 7 days was never reaped (unbounded growth)")
	}
}
