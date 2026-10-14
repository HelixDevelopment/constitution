package main

// Second-review fixes for label-mcp: core finding 4 (an explicit alias pins;
// only alias-less roots follow — CONTRACT §4.2), the follow_active default
// (adapters-review mutant N1) and adapters-review finding J (line-size cap).

import (
	"strings"
	"testing"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/state"
)

func TestRegisterExplicitAliasPinsAliaslessFollows(t *testing.T) {
	s, _ := newTestServer(t)
	one(t, s, "label_switch_alias", map[string]any{"alias": "claude1", "model": "sonnet", "effort": "low"})
	_, p, txt := one(t, s, "label_register", map[string]any{"id": "x", "kind": "agent", "track": "2", "branch": "b",
		"alias": "claude2", "model": "opus", "effort": "high"})
	if p["label"] != "(T2/b - claude2 - opus - high)" {
		t.Fatalf("explicit alias/model/effort ignored: %s", txt)
	}
	// N1: an alias-less register FOLLOWS by default
	_, f, txt := one(t, s, "label_register", map[string]any{"id": "f", "kind": "agent", "track": "2", "branch": "b"})
	if f["label"] != "(T2/b - claude1 - sonnet - low)" || f["follow_active"] != true {
		t.Fatalf("alias-less register does not follow the active context: %s", txt)
	}
	one(t, s, "label_switch_alias", map[string]any{"alias": "claude3"})
	_, x, _ := one(t, s, "label_get", map[string]any{"id": "x"})
	_, f2, _ := one(t, s, "label_get", map[string]any{"id": "f"})
	if x["label"] != "(T2/b - claude2 - opus - high)" || !strings.Contains(f2["label"].(string), "claude3") {
		t.Fatalf("after switch: pinned=%v follower=%v", x["label"], f2["label"])
	}
	// an explicit follow_active=true still wins
	_, g, txt := one(t, s, "label_register", map[string]any{"id": "g", "kind": "agent", "alias": "claude9", "follow_active": true})
	if !strings.Contains(g["label"].(string), "claude3") {
		t.Fatalf("explicit follow_active=true ignored: %s", txt)
	}
}

// Finding J: a request line over MaxLineBytes is answered with ONE
// invalid-request error and discarded without being buffered whole; the
// server keeps serving the next line.
func TestOversizedLineRejectedAndServingContinues(t *testing.T) {
	s, _ := newTestServer(t)
	big := `{"jsonrpc":"2.0","id":7,"method":"ping","params":{"pad":"` + strings.Repeat("x", MaxLineBytes+10) + `"}}`
	r := rpc(t, s, big, `{"jsonrpc":"2.0","id":8,"method":"ping"}`)
	if len(r) != 2 {
		t.Fatalf("want 2 responses (error + ping), got %d: %v", len(r), r)
	}
	var sawErr, sawPing bool
	for _, m := range r {
		if e, ok := m["error"].(map[string]any); ok && e["code"] == float64(-32600) && strings.Contains(e["message"].(string), "too large") {
			sawErr = true
		}
		if m["id"] == float64(8) && m["result"] != nil {
			sawPing = true
		}
	}
	if !sawErr || !sawPing {
		t.Fatalf("oversized line handling: %v", r)
	}
}

// M8 (re-proof): a pid outside 0..state.MaxPID is refused by the MCP ARGUMENT
// check itself, not only by the store behind it — the message names the
// argument, so the test tells the two layers apart.
func TestPidOutOfRangeRefusedAtArgumentLayer(t *testing.T) {
	s, _ := newTestServer(t)
	for _, pid := range []any{float64(-4), float64(state.MaxPID + 1)} {
		isErr, _, txt := one(t, s, "label_register", map[string]any{"id": "p", "kind": "session", "pid": pid})
		if !isErr || !strings.Contains(txt, `argument "pid"`) {
			t.Fatalf("pid %v: want an argument-level error naming \"pid\", got isErr=%v %q", pid, isErr, txt)
		}
	}
	if isErr, _, txt := one(t, s, "label_register", map[string]any{"id": "q", "kind": "session", "pid": float64(state.MaxPID)}); isErr {
		t.Fatalf("pid MaxPID must be accepted: %s", txt)
	}
}
