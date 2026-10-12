package main

// Protocol-conformance + tool tests for label-mcp (tests-first, §11.4.43/§11.4.224).
// Every test uses its own temp LABEL_SYNC_DIR; nothing touches a real state dir.

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/state"
)

func newTestServer(t *testing.T) (*server, string) {
	t.Helper()
	dir := t.TempDir()
	return newServer(state.Options{Dir: dir}), dir
}

// rpc runs the given raw lines through Serve and returns the decoded response lines.
func rpc(t *testing.T, s *server, lines ...string) []map[string]any {
	t.Helper()
	var out bytes.Buffer
	in := strings.NewReader(strings.Join(lines, "\n") + "\n")
	if err := s.Serve(in, &out); err != nil {
		t.Fatalf("Serve: %v", err)
	}
	var res []map[string]any
	for _, l := range strings.Split(strings.TrimSpace(out.String()), "\n") {
		if strings.TrimSpace(l) == "" {
			continue
		}
		var m map[string]any
		if err := json.Unmarshal([]byte(l), &m); err != nil {
			t.Fatalf("response is not JSON: %q: %v", l, err)
		}
		res = append(res, m)
	}
	return res
}

func call(id int, tool string, args map[string]any) string {
	b, _ := json.Marshal(map[string]any{"jsonrpc": "2.0", "id": id, "method": "tools/call",
		"params": map[string]any{"name": tool, "arguments": args}})
	return string(b)
}

// toolResult decodes a tools/call response into (isError, parsed JSON payload, raw text).
func toolResult(t *testing.T, resp map[string]any) (bool, map[string]any, string) {
	t.Helper()
	if resp["error"] != nil {
		t.Fatalf("expected a tool result, got JSON-RPC error: %v", resp["error"])
	}
	r := resp["result"].(map[string]any)
	isErr, _ := r["isError"].(bool)
	c := r["content"].([]any)
	if len(c) != 1 {
		t.Fatalf("expected one content block, got %d", len(c))
	}
	blk := c[0].(map[string]any)
	if blk["type"] != "text" {
		t.Fatalf("content type = %v", blk["type"])
	}
	txt := blk["text"].(string)
	var payload map[string]any
	_ = json.Unmarshal([]byte(txt), &payload)
	return isErr, payload, txt
}

func one(t *testing.T, s *server, tool string, args map[string]any) (bool, map[string]any, string) {
	t.Helper()
	r := rpc(t, s, call(1, tool, args))
	if len(r) != 1 {
		t.Fatalf("want 1 response, got %d", len(r))
	}
	return toolResult(t, r[0])
}

func TestInitializeHandshake(t *testing.T) {
	s, _ := newTestServer(t)
	r := rpc(t, s,
		`{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}`,
		`{"jsonrpc":"2.0","method":"notifications/initialized"}`,
		`{"jsonrpc":"2.0","id":"p","method":"ping"}`)
	if len(r) != 2 { // the notification MUST NOT be answered
		t.Fatalf("want 2 responses (initialize, ping), got %d: %v", len(r), r)
	}
	res := r[0]["result"].(map[string]any)
	if res["protocolVersion"] != "2024-11-05" {
		t.Fatalf("protocolVersion = %v", res["protocolVersion"])
	}
	if _, ok := res["capabilities"].(map[string]any)["tools"]; !ok {
		t.Fatalf("capabilities.tools missing: %v", res)
	}
	si := res["serverInfo"].(map[string]any)
	if si["name"] != "label-mcp" || si["version"] == "" {
		t.Fatalf("serverInfo = %v", si)
	}
	if r[0]["jsonrpc"] != "2.0" || r[0]["id"].(float64) != 0 {
		t.Fatalf("envelope = %v", r[0])
	}
	if r[1]["id"] != "p" || r[1]["result"] == nil {
		t.Fatalf("ping response (string id echoed) = %v", r[1])
	}
}

func TestInitializeOlderClientVersionStillGets20241105(t *testing.T) {
	s, _ := newTestServer(t)
	r := rpc(t, s, `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}`)
	if r[0]["result"].(map[string]any)["protocolVersion"] != "2024-11-05" {
		t.Fatalf("server must answer with the version it supports: %v", r[0])
	}
}

func TestUnknownMethod32601(t *testing.T) {
	s, _ := newTestServer(t)
	r := rpc(t, s, `{"jsonrpc":"2.0","id":7,"method":"resources/list"}`,
		`{"jsonrpc":"2.0","method":"notifications/unknown"}`)
	if len(r) != 1 { // unknown NOTIFICATION is silently ignored
		t.Fatalf("want 1 response, got %d: %v", len(r), r)
	}
	e := r[0]["error"].(map[string]any)
	if e["code"].(float64) != -32601 || r[0]["id"].(float64) != 7 {
		t.Fatalf("error = %v", r[0])
	}
}

func TestMalformedJSON32700AndServerKeepsServing(t *testing.T) {
	s, _ := newTestServer(t)
	r := rpc(t, s, `{"jsonrpc":"2.0","id":1,"method":`, `not json at all`, `{"jsonrpc":"2.0","id":2,"method":"ping"}`)
	if len(r) != 3 {
		t.Fatalf("want 3 responses, got %d: %v", len(r), r)
	}
	for i := 0; i < 2; i++ {
		e := r[i]["error"].(map[string]any)
		if e["code"].(float64) != -32700 {
			t.Fatalf("resp %d code = %v", i, e["code"])
		}
		if v, present := r[i]["id"]; !present || v != nil {
			t.Fatalf("parse error must carry id:null, got %v", r[i])
		}
	}
	if r[2]["id"].(float64) != 2 || r[2]["result"] == nil {
		t.Fatalf("server did not keep serving after bad input: %v", r[2])
	}
}

func TestInvalidRequest32600(t *testing.T) {
	s, _ := newTestServer(t)
	r := rpc(t, s, `{"jsonrpc":"2.0","id":1}`, `{"jsonrpc":"1.0","id":2,"method":"ping"}`, `"hello"`, `42`)
	if len(r) != 4 {
		t.Fatalf("want 4 responses, got %d: %v", len(r), r)
	}
	for i, x := range r {
		if x["error"] == nil {
			t.Fatalf("resp %d must be an error: %v", i, x)
		}
	}
	for _, i := range []int{0, 1} {
		if r[i]["error"].(map[string]any)["code"].(float64) != -32600 {
			t.Fatalf("resp %d code = %v", i, r[i]["error"])
		}
	}
}

func TestBatchRequest(t *testing.T) {
	s, _ := newTestServer(t)
	var out bytes.Buffer
	if err := s.Serve(strings.NewReader(`[{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","id":2,"method":"nope"}]`+"\n"), &out); err != nil {
		t.Fatal(err)
	}
	var arr []map[string]any
	if err := json.Unmarshal(bytes.TrimSpace(out.Bytes()), &arr); err != nil || len(arr) != 2 {
		t.Fatalf("batch response = %q err=%v", out.String(), err)
	}
}

func TestToolsListSchema(t *testing.T) {
	s, _ := newTestServer(t)
	r := rpc(t, s, `{"jsonrpc":"2.0","id":1,"method":"tools/list"}`)
	tools := r[0]["result"].(map[string]any)["tools"].([]any)
	want := map[string][]string{
		"label_get": nil, "label_list": nil, "label_switch_alias": {"alias"},
		"label_register": {"id", "kind"}, "label_heartbeat": {"id"}, "label_done": {"id"}, "label_active": nil,
	}
	got := map[string]map[string]any{}
	for _, x := range tools {
		m := x.(map[string]any)
		got[m["name"].(string)] = m
		if m["description"] == "" || m["description"] == nil {
			t.Fatalf("tool %v has no description", m["name"])
		}
		sch := m["inputSchema"].(map[string]any)
		if sch["type"] != "object" {
			t.Fatalf("tool %v inputSchema.type = %v", m["name"], sch["type"])
		}
		if _, ok := sch["properties"].(map[string]any); !ok {
			t.Fatalf("tool %v has no properties", m["name"])
		}
	}
	for name, req := range want {
		m, ok := got[name]
		if !ok {
			t.Fatalf("tool %q missing from tools/list (have %v)", name, keys(got))
		}
		var haveReq []string
		if rr, ok := m["inputSchema"].(map[string]any)["required"].([]any); ok {
			for _, v := range rr {
				haveReq = append(haveReq, v.(string))
			}
		}
		if strings.Join(haveReq, ",") != strings.Join(req, ",") {
			t.Fatalf("tool %q required = %v want %v", name, haveReq, req)
		}
	}
	if len(got) != len(want) {
		t.Fatalf("tool set = %v", keys(got))
	}
}

func keys(m map[string]map[string]any) []string {
	var k []string
	for x := range m {
		k = append(k, x)
	}
	return k
}

func TestToolsCallProtocolErrors(t *testing.T) {
	s, _ := newTestServer(t)
	r := rpc(t, s,
		`{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"no_such_tool","arguments":{}}}`,
		`{"jsonrpc":"2.0","id":2,"method":"tools/call","params":"oops"}`,
		`{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"arguments":{}}}`,
		`{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"label_get","arguments":"x"}}`)
	for i, x := range r {
		e, ok := x["error"].(map[string]any)
		if !ok || e["code"].(float64) != -32602 {
			t.Fatalf("resp %d = %v, want -32602", i, x)
		}
	}
}

func reg(t *testing.T, s *server, id, alias string, extra map[string]any) string {
	t.Helper()
	a := map[string]any{"id": id, "kind": "session", "alias": alias, "model": "sonnet", "effort": "high",
		"track": "3", "branch": "main", "follow_active": false}
	for k, v := range extra {
		a[k] = v
	}
	isErr, _, txt := one(t, s, "label_register", a)
	if isErr {
		t.Fatalf("register %s: %s", id, txt)
	}
	return txt
}

func TestRegisterHappyAndLabel(t *testing.T) {
	s, _ := newTestServer(t)
	isErr, p, txt := one(t, s, "label_register", map[string]any{"id": "s1", "kind": "session", "alias": "claude2",
		"model": "sonnet", "effort": "xhigh", "track": "3", "branch": "feature/x", "follow_active": false})
	if isErr {
		t.Fatalf("unexpected error: %s", txt)
	}
	if p["label"] != "(T3/feature/x - claude2 - sonnet - xhigh)" {
		t.Fatalf("label = %v", p["label"])
	}
}

func TestRegisterErrors(t *testing.T) {
	s, _ := newTestServer(t)
	for name, args := range map[string]map[string]any{
		"bad kind":   {"id": "x", "kind": "bogus"},
		"missing id": {"kind": "session"},
		"bad pid":    {"id": "x", "kind": "session", "pid": -4},
		"bad state":  {"id": "x", "kind": "session", "state": "zzz"},
	} {
		isErr, _, txt := one(t, s, "label_register", args)
		if !isErr || txt == "" {
			t.Fatalf("%s: want isError with message, got isErr=%v %q", name, isErr, txt)
		}
	}
}

func TestHeartbeatAndDone(t *testing.T) {
	s, _ := newTestServer(t)
	reg(t, s, "s1", "claude1", nil)
	if isErr, _, txt := one(t, s, "label_heartbeat", map[string]any{"id": "s1", "state": "idle"}); isErr {
		t.Fatalf("heartbeat: %s", txt)
	}
	_, p, _ := one(t, s, "label_get", map[string]any{"id": "s1"})
	if p["state"] != "idle" {
		t.Fatalf("state after heartbeat = %v", p["state"])
	}
	if isErr, _, _ := one(t, s, "label_heartbeat", map[string]any{"id": "ghost"}); !isErr {
		t.Fatal("heartbeat of unknown id must be an error")
	}
	if isErr, _, txt := one(t, s, "label_done", map[string]any{"id": "s1"}); isErr {
		t.Fatalf("done: %s", txt)
	}
	_, p, _ = one(t, s, "label_get", map[string]any{"id": "s1"})
	if p["state"] != "done" {
		t.Fatalf("state after done = %v", p["state"])
	}
	if isErr, _, _ := one(t, s, "label_done", map[string]any{"id": "ghost"}); !isErr {
		t.Fatal("done of unknown id must be an error")
	}
}

func TestGetByIDBySessionIDAndErrors(t *testing.T) {
	s, _ := newTestServer(t)
	reg(t, s, "ent-1", "claude1", map[string]any{"session_id": "sess-xyz"})
	_, p, _ := one(t, s, "label_get", map[string]any{"id": "ent-1"})
	if p["id"] != "ent-1" || p["label"] == "" {
		t.Fatalf("by id = %v", p)
	}
	_, p, _ = one(t, s, "label_get", map[string]any{"session_id": "sess-xyz"})
	if p["id"] != "ent-1" {
		t.Fatalf("by session_id = %v", p)
	}
	for name, a := range map[string]map[string]any{"neither": {}, "unknown id": {"id": "nope"}, "unknown session": {"session_id": "nope"}} {
		if isErr, _, txt := one(t, s, "label_get", a); !isErr || txt == "" {
			t.Fatalf("%s: want isError, got %v %q", name, isErr, txt)
		}
	}
}

func listIDs(t *testing.T, s *server, args map[string]any) []string {
	t.Helper()
	isErr, p, txt := one(t, s, "label_list", args)
	if isErr {
		t.Fatalf("list: %s", txt)
	}
	var ids []string
	for _, e := range p["entities"].([]any) {
		ids = append(ids, e.(map[string]any)["id"].(string))
	}
	return ids
}

func TestListFilters(t *testing.T) {
	s, _ := newTestServer(t)
	reg(t, s, "a", "claude1", nil)
	reg(t, s, "b", "claude2", nil)
	reg(t, s, "c", "claude2", map[string]any{"kind": "agent"})
	if got := listIDs(t, s, map[string]any{}); len(got) != 3 {
		t.Fatalf("unfiltered = %v", got)
	}
	if got := listIDs(t, s, map[string]any{"alias": "claude2"}); strings.Join(got, ",") != "b,c" {
		t.Fatalf("alias filter = %v (must exclude claude1)", got)
	}
	if got := listIDs(t, s, map[string]any{"kind": "agent"}); strings.Join(got, ",") != "c" {
		t.Fatalf("kind filter = %v", got)
	}
	if got := listIDs(t, s, map[string]any{"kind": "session", "alias": "claude2"}); strings.Join(got, ",") != "b" {
		t.Fatalf("combined filter = %v", got)
	}
	if got := listIDs(t, s, map[string]any{"alias": "nobody"}); len(got) != 0 {
		t.Fatalf("no-match = %v", got)
	}
	if isErr, _, _ := one(t, s, "label_list", map[string]any{"kind": "bogus"}); !isErr {
		t.Fatal("invalid kind filter must be an error")
	}
}

func TestSwitchAliasRelabelsFollowersThroughTheBus(t *testing.T) {
	s, dir := newTestServer(t)
	reg(t, s, "follower", "claude1", map[string]any{"follow_active": true})
	reg(t, s, "pinned", "claude1", map[string]any{"follow_active": false})
	seqBefore := readSeq(t, dir)
	isErr, p, txt := one(t, s, "label_switch_alias", map[string]any{"alias": "claude2", "model": "opus", "effort": "max"})
	if isErr {
		t.Fatalf("switch: %s", txt)
	}
	if p["alias"] != "claude2" {
		t.Fatalf("switch result = %v", p)
	}
	if readSeq(t, dir) <= seqBefore {
		t.Fatal("seq did not advance: the switch did not go through the bus")
	}
	ev, _ := os.ReadFile(filepath.Join(dir, "events.jsonl"))
	if !strings.Contains(string(ev), `"type":"alias_switch"`) {
		t.Fatalf("events.jsonl has no alias_switch event:\n%s", ev)
	}
	_, f, _ := one(t, s, "label_get", map[string]any{"id": "follower"})
	if f["label"] != "(T3/main - claude2 - opus - max)" {
		t.Fatalf("follower label = %v (alias switch must relabel followers)", f["label"])
	}
	_, pi, _ := one(t, s, "label_get", map[string]any{"id": "pinned"})
	if !strings.Contains(pi["label"].(string), "claude1") {
		t.Fatalf("pinned label changed: %v", pi["label"])
	}
	_, a, _ := one(t, s, "label_active", map[string]any{})
	if a["alias"] != "claude2" || a["model"] != "opus" || a["effort"] != "max" {
		t.Fatalf("active = %v", a)
	}
}

func TestSwitchAliasUnspecifiedModelRendersUnknown(t *testing.T) {
	s, _ := newTestServer(t)
	reg(t, s, "f", "claude1", map[string]any{"follow_active": true})
	one(t, s, "label_switch_alias", map[string]any{"alias": "claude3"})
	_, f, _ := one(t, s, "label_get", map[string]any{"id": "f"})
	if f["label"] != "(T3/main - claude3 - ? - ?)" {
		t.Fatalf("label = %v (a switch must never invent model/effort)", f["label"])
	}
}

func TestSwitchAliasErrors(t *testing.T) {
	s, dir := newTestServer(t)
	for name, a := range map[string]map[string]any{"empty": {"alias": ""}, "missing": {}, "wrong type": {"alias": 5}} {
		if isErr, _, txt := one(t, s, "label_switch_alias", a); !isErr || txt == "" {
			t.Fatalf("%s: want isError, got %v %q", name, isErr, txt)
		}
	}
	if b, err := os.ReadFile(filepath.Join(dir, "events.jsonl")); err == nil && strings.Contains(string(b), "alias_switch") {
		t.Fatal("a rejected switch must not be logged")
	}
}

func TestActiveWhenNothingActive(t *testing.T) {
	s, _ := newTestServer(t)
	isErr, p, txt := one(t, s, "label_active", map[string]any{})
	if isErr {
		t.Fatalf("label_active on an empty store must succeed: %s", txt)
	}
	if p["alias"] != "" {
		t.Fatalf("active = %v", p)
	}
}

func readSeq(t *testing.T, dir string) uint64 {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(dir, "seq"))
	if err != nil {
		return 0
	}
	var n uint64
	fmt.Sscanf(strings.TrimSpace(string(b)), "%d", &n)
	return n
}

func TestStateDirUnusableIsToolErrorNotCrash(t *testing.T) {
	f := filepath.Join(t.TempDir(), "afile")
	if err := os.WriteFile(f, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	s := newServer(state.Options{Dir: filepath.Join(f, "sub")}) // a path UNDER a regular file
	r := rpc(t, s, `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}`, call(2, "label_list", map[string]any{}))
	if r[0]["result"] == nil {
		t.Fatalf("initialize must work without a usable state dir: %v", r[0])
	}
	isErr, _, txt := toolResult(t, r[1])
	if !isErr || !strings.Contains(strings.ToLower(txt), "cannot determine") {
		t.Fatalf("want isError 'cannot determine', got %v %q", isErr, txt)
	}
}

func TestConcurrentToolCalls(t *testing.T) {
	s, dir := newTestServer(t)
	const n = 60
	var lines []string
	for i := 0; i < n; i++ {
		lines = append(lines, call(i, "label_register", map[string]any{"id": fmt.Sprintf("c%03d", i), "kind": "stream",
			"alias": "claude1", "track": "1", "branch": "main", "follow_active": false}))
	}
	r := rpc(t, s, lines...)
	if len(r) != n {
		t.Fatalf("want %d responses, got %d", n, len(r))
	}
	seen := map[int]bool{}
	for _, x := range r {
		if isErr, _, txt := toolResult(t, x); isErr {
			t.Fatalf("concurrent register failed: %s", txt)
		}
		seen[int(x["id"].(float64))] = true
	}
	if len(seen) != n {
		t.Fatalf("response ids not unique/complete: %d", len(seen))
	}
	st, _ := state.Open(state.Options{Dir: dir})
	snap, err := st.Snapshot()
	if err != nil || len(snap.Entities) != n {
		t.Fatalf("snapshot entities=%d err=%v", len(snap.Entities), err)
	}
	if err := st.Verify(); err != nil {
		t.Fatalf("verify after concurrent writes: %v", err)
	}
}

func TestEOFCleanExitWithInFlightCalls(t *testing.T) {
	s, _ := newTestServer(t)
	pr, pw := io.Pipe()
	var out bytes.Buffer
	var mu sync.Mutex
	done := make(chan error, 1)
	go func() { done <- s.Serve(pr, &lockedWriter{&mu, &out}) }()
	fmt.Fprintln(pw, call(1, "label_register", map[string]any{"id": "e1", "kind": "shell", "alias": "claude1"}))
	pw.Close() // EOF immediately
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("Serve on EOF returned %v, want nil", err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("Serve did not return on stdin EOF")
	}
	mu.Lock()
	defer mu.Unlock()
	if !strings.Contains(out.String(), `"id":1`) {
		t.Fatalf("in-flight call was dropped at EOF: %q", out.String())
	}
}

type lockedWriter struct {
	mu *sync.Mutex
	w  io.Writer
}

func (l *lockedWriter) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.w.Write(p)
}

func TestLargeLine(t *testing.T) {
	s, _ := newTestServer(t)
	big := strings.Repeat("x", 300_000)
	r := rpc(t, s, call(1, "label_get", map[string]any{"id": big}))
	if len(r) != 1 {
		t.Fatalf("want 1 response for a 300KB request line, got %d", len(r))
	}
	if isErr, _, _ := toolResult(t, r[0]); !isErr {
		t.Fatal("unknown huge id must be a tool error, not a crash")
	}
}

func TestEmptyLinesIgnoredAndCRLF(t *testing.T) {
	s, _ := newTestServer(t)
	var out bytes.Buffer
	if err := s.Serve(strings.NewReader("\n\r\n"+`{"jsonrpc":"2.0","id":1,"method":"ping"}`+"\r\n\n"), &out); err != nil {
		t.Fatal(err)
	}
	if strings.Count(out.String(), "\n") != 1 {
		t.Fatalf("output = %q", out.String())
	}
}

// ── real-binary stdio test (the actual process boundary) ─────────────────────

func TestBinaryStdio(t *testing.T) {
	if testing.Short() {
		t.Skip("-short")
	}
	bin := filepath.Join(t.TempDir(), "label-mcp")
	b := exec.Command("go", "build", "-o", bin, ".")
	b.Env = append(os.Environ(), "GOPROXY=off", "GOFLAGS=-buildvcs=false")
	if out, err := b.CombinedOutput(); err != nil {
		t.Fatalf("build: %v\n%s", err, out)
	}
	dir := t.TempDir()
	c := exec.Command(bin)
	c.Env = append(os.Environ(), "LABEL_SYNC_DIR="+dir)
	in, _ := c.StdinPipe()
	var out, errb bytes.Buffer
	c.Stdout, c.Stderr = &out, &errb
	if err := c.Start(); err != nil {
		t.Fatal(err)
	}
	fmt.Fprintln(in, `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}`)
	fmt.Fprintln(in, `{"jsonrpc":"2.0","method":"notifications/initialized"}`)
	fmt.Fprintln(in, call(2, "label_register", map[string]any{"id": "bin1", "kind": "session", "alias": "claude2", "model": "opus", "effort": "high", "follow_active": false}))
	fmt.Fprintln(in, call(3, "label_active", map[string]any{}))
	in.Close()
	done := make(chan error, 1)
	go func() { done <- c.Wait() }()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("binary exit: %v stderr=%s", err, errb.String())
		}
	case <-time.After(30 * time.Second):
		_ = c.Process.Kill()
		t.Fatal("binary did not exit on stdin EOF")
	}
	lines := strings.Split(strings.TrimSpace(out.String()), "\n")
	if len(lines) != 3 {
		t.Fatalf("want 3 stdout lines, got %d: %q (stderr %q)", len(lines), out.String(), errb.String())
	}
	if strings.Contains(out.String(), "\x1b") {
		t.Fatal("stdout must carry only JSON-RPC")
	}
	if !strings.Contains(lines[1], "claude2") {
		t.Fatalf("register response = %s", lines[1])
	}
	st, _ := state.Open(state.Options{Dir: dir})
	if _, err := st.Snapshot(); err != nil {
		t.Fatal(err)
	}
}
