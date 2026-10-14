package state

// Re-review (third review) finding 2: a process that is alive in ANOTHER PID
// namespace (a container sharing the state dir) is not provably dead to a
// writer outside that namespace — its pid means nothing there.

import (
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
