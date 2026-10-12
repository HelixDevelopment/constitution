// scripts/label-sync/mcp/label-mcp/server.go
//
// Purpose : MCP (Model Context Protocol) server for the constitution label-sync
//
//	system (§11.4.182). Exposes the live label bus to ANY MCP-capable
//	agent so it can read the current label/alias, list labelled
//	entities, switch the operator's active alias and register/
//	heartbeat/finish its own entity. Implemented directly on the CORE
//	Go packages (internal/state, internal/model) — the same code path
//	`labelctl` uses, so MCP and CLI can never disagree.
//
// Usage   : label-mcp            (speaks JSON-RPC 2.0 on stdin/stdout, one JSON
//
//	document per line; protocol 2024-11-05)
//
// Inputs  : stdin JSON-RPC; env LABEL_SYNC_DIR (state dir, CONTRACT §1),
//
//	LABEL_SYNC_TTL, LABEL_SYNC_DONE_RETENTION.
//
// Outputs : stdout carries ONLY JSON-RPC responses (never logs, never escapes);
//
//	diagnostics go to stderr.
//
// Exit    : 0 on stdin EOF (after answering every in-flight call), 2 on a
//
//	stdout write failure. A broken state dir NEVER crashes the server:
//	every tool then returns isError=true "cannot determine ..." (2 is
//	never a pass, §11.4.6) while initialize/ping keep working.
//
// Side-effects: tool calls append to $LABEL_SYNC_DIR/events.jsonl (flock'd,
//
//	atomic snapshot) — exactly what labelctl does. No network.
//
// Deps    : Go stdlib only.
// Cross-refs: §11.4.182, §11.4.116, §11.4.233, §11.4.18,
//
//	docs/label-sync/MCP.md, docs/label-sync/CONTRACT.md.
//
// Classification: universal (§11.4.17).
package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"sync"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/state"
)

const (
	protocolVersion = "2024-11-05"
	serverName      = "label-mcp"
	serverVersion   = "1.0.0"
)

// JSON-RPC 2.0 error codes.
const (
	errParse          = -32700
	errInvalidRequest = -32600
	errMethodNotFound = -32601
	errInvalidParams  = -32602
)

type server struct {
	opts  state.Options
	once  sync.Once
	st    *state.Store
	stErr error

	// arrival-order scheduler (see sched)
	smu      sync.Mutex
	lastMut  chan struct{}
	inflight map[chan struct{}]struct{}
}

// sched implements READ-AFTER-WRITE ordering for pipelined requests. A client
// that writes register, switch and get to stdin without waiting for answers must
// see them applied in arrival order. Rules: a MUTATING request (register,
// heartbeat, done, switch_alias, any batch) starts only after EVERY earlier
// request has finished; any other request starts after the latest earlier
// mutation has finished and then runs concurrently with other reads. The
// returned func MUST be called when the request completes.
func (s *server) sched(mutating bool) (wait []chan struct{}, finish func()) {
	done := make(chan struct{})
	s.smu.Lock()
	if s.inflight == nil {
		s.inflight = map[chan struct{}]struct{}{}
	}
	if mutating {
		for c := range s.inflight {
			wait = append(wait, c)
		}
		s.lastMut = done
	} else if s.lastMut != nil {
		wait = append(wait, s.lastMut)
	}
	s.inflight[done] = struct{}{}
	s.smu.Unlock()
	return wait, func() {
		s.smu.Lock()
		delete(s.inflight, done)
		s.smu.Unlock()
		close(done)
	}
}

// isMutating peeks at a raw request line (cheaply, without trusting it).
func isMutating(raw []byte) bool {
	if len(raw) > 0 && raw[0] == '[' {
		return true
	}
	var p struct {
		Method string `json:"method"`
		Params struct {
			Name string `json:"name"`
		} `json:"params"`
	}
	if json.Unmarshal(raw, &p) != nil || p.Method != "tools/call" {
		return false
	}
	switch p.Params.Name {
	case "label_register", "label_heartbeat", "label_done", "label_switch_alias":
		return true
	}
	return false
}

func newServer(o state.Options) *server { return &server{opts: o} }

// store opens the state store lazily so initialize/ping work with a broken dir.
func (s *server) store() (*state.Store, error) {
	s.once.Do(func() { s.st, s.stErr = state.Open(s.opts) })
	if s.stErr != nil {
		return nil, fmt.Errorf("cannot determine: label state dir unusable: %v", s.stErr)
	}
	return s.st, nil
}

type request struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Method  *string         `json:"method"`
	Params  json.RawMessage `json:"params"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// response is marshalled by MarshalJSON so that "result" is ALWAYS present on
// success (even when it is an empty object, e.g. ping) and absent on error.
type response struct {
	ID     json.RawMessage
	Result any
	Error  *rpcError
}

func (r *response) MarshalJSON() ([]byte, error) {
	if r.Error != nil {
		return json.Marshal(struct {
			JSONRPC string          `json:"jsonrpc"`
			ID      json.RawMessage `json:"id"`
			Error   *rpcError       `json:"error"`
		}{"2.0", r.ID, r.Error})
	}
	return json.Marshal(struct {
		JSONRPC string          `json:"jsonrpc"`
		ID      json.RawMessage `json:"id"`
		Result  any             `json:"result"`
	}{"2.0", r.ID, r.Result})
}

func errResp(id json.RawMessage, code int, msg string) *response {
	if len(id) == 0 {
		id = json.RawMessage("null")
	}
	return &response{ID: id, Error: &rpcError{Code: code, Message: msg}}
}

// Serve reads newline-delimited JSON-RPC from r and writes responses to w until
// EOF. Reads EXECUTE concurrently; mutations are ordered after everything that
// arrived before them and reads after the latest mutation (see sched), so a
// client that pipelines dependent calls gets read-after-write. Responses are
// EMITTED in request order, so output is deterministic and a slow call never
// corrupts framing. It returns nil on clean EOF after
// every in-flight request has been answered.
func (s *server) Serve(r io.Reader, w io.Writer) error {
	slots := make(chan chan []byte, 4096)
	var werr error
	wdone := make(chan struct{})
	go func() {
		defer close(wdone)
		for slot := range slots {
			b := <-slot
			if b == nil || werr != nil {
				continue
			}
			if _, err := w.Write(append(b, '\n')); err != nil {
				werr = err
			}
		}
	}()
	enc := func(v any) []byte {
		b, err := json.Marshal(v)
		if err != nil {
			b, _ = json.Marshal(errResp(nil, -32603, "internal error: "+err.Error()))
		}
		return b
	}
	br := bufio.NewReaderSize(r, 1<<16)
	var rerr error
	for {
		line, err := br.ReadBytes('\n')
		if t := bytes.TrimSpace(line); len(t) > 0 {
			raw := append([]byte(nil), t...)
			slot := make(chan []byte, 1)
			slots <- slot
			wait, finish := s.sched(isMutating(raw)) // registered in ARRIVAL order, before the goroutine starts
			go func() {
				defer finish()
				for _, c := range wait {
					<-c
				}
				var out []byte
				s.handleLine(raw, func(v any) { out = enc(v) })
				slot <- out
			}()
		}
		if err != nil {
			if !errors.Is(err, io.EOF) {
				rerr = err
			}
			break
		}
	}
	close(slots)
	<-wdone
	if werr != nil {
		return werr
	}
	return rerr
}

func (s *server) handleLine(raw []byte, write func(any)) {
	if raw[0] == '[' { // JSON-RPC batch
		var items []json.RawMessage
		if err := json.Unmarshal(raw, &items); err != nil {
			write(errResp(nil, errParse, "parse error: "+err.Error()))
			return
		}
		if len(items) == 0 {
			write(errResp(nil, errInvalidRequest, "empty batch"))
			return
		}
		var resp []*response // in order: a batch is one barrier, its items run sequentially
		for _, it := range items {
			if x := s.handleOne(it); x != nil {
				resp = append(resp, x)
			}
		}
		if len(resp) > 0 {
			write(resp)
		}
		return
	}
	if resp := s.handleOne(raw); resp != nil {
		write(resp)
	}
}

// handleOne returns nil for notifications (no id).
func (s *server) handleOne(raw []byte) *response {
	var probe any
	if err := json.Unmarshal(raw, &probe); err != nil {
		return errResp(nil, errParse, "parse error: "+err.Error())
	}
	if _, isObj := probe.(map[string]any); !isObj {
		return errResp(nil, errInvalidRequest, "request must be a JSON object")
	}
	var req request
	if err := json.Unmarshal(raw, &req); err != nil {
		return errResp(nil, errInvalidRequest, "invalid request: "+err.Error())
	}
	isNotification := len(req.ID) == 0
	if req.JSONRPC != "2.0" || req.Method == nil || *req.Method == "" {
		if isNotification {
			return nil
		}
		return errResp(req.ID, errInvalidRequest, `invalid request: "jsonrpc":"2.0" and a string "method" are required`)
	}
	result, rerr := s.dispatch(*req.Method, req.Params)
	if isNotification {
		return nil
	}
	if rerr != nil {
		return errResp(req.ID, rerr.Code, rerr.Message)
	}
	return &response{ID: req.ID, Result: result}
}

func (s *server) dispatch(method string, params json.RawMessage) (any, *rpcError) {
	switch method {
	case "initialize":
		return map[string]any{
			"protocolVersion": protocolVersion,
			"capabilities":    map[string]any{"tools": map[string]any{"listChanged": false}},
			"serverInfo":      map[string]any{"name": serverName, "version": serverVersion},
			"instructions":    "Live §11.4.182 label bus. Prefix Agent/Task descriptions with the label from label_get; use label_switch_alias to switch the operator's active alias (every follower relabels immediately).",
		}, nil
	case "ping":
		return map[string]any{}, nil
	case "tools/list":
		return map[string]any{"tools": toolDefs()}, nil
	case "tools/call":
		return s.callTool(params)
	case "notifications/initialized", "notifications/cancelled":
		return nil, nil
	}
	return nil, &rpcError{errMethodNotFound, "method not found: " + method}
}

// ── tools ────────────────────────────────────────────────────────────────────

type toolDef struct {
	Name        string         `json:"name"`
	Description string         `json:"description"`
	InputSchema map[string]any `json:"inputSchema"`
}

func str(desc string) map[string]any { return map[string]any{"type": "string", "description": desc} }

func schema(required []string, props map[string]any) map[string]any {
	s := map[string]any{"type": "object", "properties": props}
	if len(required) > 0 {
		s["required"] = required
	}
	return s
}

func toolDefs() []toolDef {
	kinds := "session|agent|subagent|stream|shell|command|flow"
	return []toolDef{
		{"label_get", "Return the rendered label (and full entity) of one labelled thing, by entity id or by Claude session id. The label is `(T<N>/<branch> - <alias> - <model> - <effort>)`; unknown fields render as `?`.",
			schema(nil, map[string]any{"id": str("entity id"), "session_id": str("Claude session id (returns the session entity, else the first match)")})},
		{"label_list", "List labelled entities, optionally filtered by kind and/or by their EFFECTIVE alias.",
			schema(nil, map[string]any{"kind": str("one of " + kinds), "alias": str("effective alias, e.g. claude2")})},
		{"label_switch_alias", "Switch the operator's ACTIVE alias (and optionally model/effort). Every entity that follows the active alias is relabelled in the same write. Unspecified model/effort render as `?` — nothing is invented.",
			schema([]string{"alias"}, map[string]any{"alias": str("claude1, claude2, prov-*, ..."), "model": str("opus|sonnet|haiku|fable|<provider model>"), "effort": str("low|medium|high|xhigh|max")})},
		{"label_register", "Register (or replace) a labelled entity. follow_active defaults to true.",
			schema([]string{"id", "kind"}, map[string]any{
				"id": str("unique caller-chosen id"), "kind": str(kinds), "parent_id": str("parent entity id"),
				"session_id": str("Claude session id"), "pid": map[string]any{"type": "integer", "description": "OS pid (>0) on this host"},
				"cwd": str("working directory"), "track": str("digits only"), "branch": str("git branch"),
				"alias": str("alias"), "model": str("model"), "effort": str("effort"),
				"follow_active": map[string]any{"type": "boolean", "description": "follow the operator's active alias (default true)"},
				"state":         str("running|idle|done|unknown"), "source": str("who reports this entity")})},
		{"label_heartbeat", "Refresh an entity's liveness (updated_at); optionally set its state.",
			schema([]string{"id"}, map[string]any{"id": str("entity id"), "state": str("running|idle|done|unknown")})},
		{"label_done", "Mark an entity finished (state=done; it is reaped after the retention window).",
			schema([]string{"id"}, map[string]any{"id": str("entity id")})},
		{"label_active", "Return the operator's ACTIVE alias/model/effort context.",
			schema(nil, map[string]any{})},
	}
}

func (s *server) callTool(params json.RawMessage) (any, *rpcError) {
	var p struct {
		Name      *string         `json:"name"`
		Arguments json.RawMessage `json:"arguments"`
	}
	if len(params) == 0 {
		return nil, &rpcError{errInvalidParams, "params required"}
	}
	if err := json.Unmarshal(params, &p); err != nil || p.Name == nil || *p.Name == "" {
		return nil, &rpcError{errInvalidParams, `params must be an object with a string "name"`}
	}
	args := map[string]any{}
	if len(p.Arguments) > 0 && string(p.Arguments) != "null" {
		if err := json.Unmarshal(p.Arguments, &args); err != nil {
			return nil, &rpcError{errInvalidParams, `"arguments" must be an object`}
		}
	}
	var h func(*server, map[string]any) (any, error)
	switch *p.Name {
	case "label_get":
		h = (*server).toolGet
	case "label_list":
		h = (*server).toolList
	case "label_switch_alias":
		h = (*server).toolSwitch
	case "label_register":
		h = (*server).toolRegister
	case "label_heartbeat":
		h = (*server).toolHeartbeat
	case "label_done":
		h = (*server).toolDone
	case "label_active":
		h = (*server).toolActive
	default:
		return nil, &rpcError{errInvalidParams, "unknown tool: " + *p.Name}
	}
	v, err := h(s, args)
	if err != nil {
		return toolText(err.Error(), true), nil
	}
	b, _ := json.Marshal(v)
	return toolText(string(b), false), nil
}

func toolText(text string, isErr bool) map[string]any {
	return map[string]any{"content": []any{map[string]any{"type": "text", "text": text}}, "isError": isErr}
}

// argStr returns the optional string argument k. A present non-string is an error.
func argStr(a map[string]any, k string) (string, bool, error) {
	v, ok := a[k]
	if !ok || v == nil {
		return "", false, nil
	}
	sv, ok := v.(string)
	if !ok {
		return "", true, fmt.Errorf("argument %q must be a string", k)
	}
	return sv, true, nil
}

func argReqStr(a map[string]any, k string) (string, error) {
	v, _, err := argStr(a, k)
	if err != nil {
		return "", err
	}
	if v == "" {
		return "", fmt.Errorf("argument %q is required", k)
	}
	return v, nil
}

func (s *server) entity(id string) (*model.Entity, error) {
	st, err := s.store()
	if err != nil {
		return nil, err
	}
	snap, err := st.Snapshot()
	if err != nil {
		return nil, fmt.Errorf("cannot determine: %v", err)
	}
	for i := range snap.Entities {
		if snap.Entities[i].ID == id {
			return &snap.Entities[i], nil
		}
	}
	return nil, fmt.Errorf("unknown id %q", id)
}

func (s *server) toolGet(a map[string]any) (any, error) {
	id, _, err := argStr(a, "id")
	if err != nil {
		return nil, err
	}
	sid, _, err := argStr(a, "session_id")
	if err != nil {
		return nil, err
	}
	if id == "" && sid == "" {
		return nil, errors.New(`one of "id" or "session_id" is required`)
	}
	if id != "" {
		return s.entity(id)
	}
	st, err := s.store()
	if err != nil {
		return nil, err
	}
	snap, err := st.Snapshot()
	if err != nil {
		return nil, fmt.Errorf("cannot determine: %v", err)
	}
	var first *model.Entity
	for i := range snap.Entities {
		e := &snap.Entities[i]
		if e.SessionID != sid {
			continue
		}
		if e.Kind == model.KindSession {
			return e, nil
		}
		if first == nil {
			first = e
		}
	}
	if first == nil {
		return nil, fmt.Errorf("no entity with session_id %q", sid)
	}
	return first, nil
}

func (s *server) toolList(a map[string]any) (any, error) {
	kind, _, err := argStr(a, "kind")
	if err != nil {
		return nil, err
	}
	alias, _, err := argStr(a, "alias")
	if err != nil {
		return nil, err
	}
	if kind != "" && !model.ValidKind(kind) {
		return nil, fmt.Errorf("invalid kind %q", kind)
	}
	st, err := s.store()
	if err != nil {
		return nil, err
	}
	snap, err := st.Snapshot()
	if err != nil {
		return nil, fmt.Errorf("cannot determine: %v", err)
	}
	out := []model.Entity{}
	for _, e := range snap.Entities {
		if kind != "" && e.Kind != kind {
			continue
		}
		if alias != "" && e.Alias != alias { // e.Alias is the EFFECTIVE alias in the snapshot
			continue
		}
		out = append(out, e)
	}
	return map[string]any{"seq": snap.Seq, "entities": out}, nil
}

func (s *server) toolSwitch(a map[string]any) (any, error) {
	alias, err := argReqStr(a, "alias")
	if err != nil {
		return nil, err
	}
	mo, _, err := argStr(a, "model")
	if err != nil {
		return nil, err
	}
	ef, _, err := argStr(a, "effort")
	if err != nil {
		return nil, err
	}
	st, err := s.store()
	if err != nil {
		return nil, err
	}
	ev, err := st.Apply(model.Event{Type: model.EvAliasSwitch, Active: &model.Active{Alias: alias, Model: mo, Effort: ef}})
	if err != nil {
		return nil, err
	}
	return map[string]any{"alias": ev.Active.Alias, "model": mo, "effort": ef, "seq": ev.Seq}, nil
}

func (s *server) toolRegister(a map[string]any) (any, error) {
	id, err := argReqStr(a, "id")
	if err != nil {
		return nil, err
	}
	kind, err := argReqStr(a, "kind")
	if err != nil {
		return nil, err
	}
	if !model.ValidKind(kind) {
		return nil, fmt.Errorf("kind must be one of session|agent|subagent|stream|shell|command|flow (got %q)", kind)
	}
	e := model.Entity{ID: id, Kind: kind, FollowActive: true}
	for k, dst := range map[string]*string{"parent_id": &e.ParentID, "session_id": &e.SessionID, "cwd": &e.Cwd,
		"track": &e.Track, "branch": &e.Branch, "alias": &e.Alias, "model": &e.Model, "effort": &e.Effort,
		"state": &e.State, "source": &e.Source} {
		v, _, err := argStr(a, k)
		if err != nil {
			return nil, err
		}
		*dst = v
	}
	if e.Source == "" {
		e.Source = "label-mcp"
	}
	if v, ok := a["pid"]; ok && v != nil {
		f, ok := v.(float64)
		if !ok || f != float64(int(f)) {
			return nil, errors.New(`argument "pid" must be an integer`)
		}
		if f < 0 {
			return nil, errors.New(`argument "pid" must be >= 0`)
		}
		e.PID = int(f)
	}
	if v, ok := a["follow_active"]; ok && v != nil {
		b, ok := v.(bool)
		if !ok {
			return nil, errors.New(`argument "follow_active" must be a boolean`)
		}
		e.FollowActive = b
	}
	e.Host, _ = os.Hostname()
	if e.Cwd == "" {
		e.Cwd, _ = os.Getwd()
	}
	st, err := s.store()
	if err != nil {
		return nil, err
	}
	if _, err := st.Apply(model.Event{Type: model.EvRegister, Entity: &e}); err != nil {
		return nil, err
	}
	return s.entity(id)
}

func (s *server) toolHeartbeat(a map[string]any) (any, error) {
	id, err := argReqStr(a, "id")
	if err != nil {
		return nil, err
	}
	stt, _, err := argStr(a, "state")
	if err != nil {
		return nil, err
	}
	patch := map[string]string{}
	if stt != "" {
		patch["state"] = stt
	}
	st, err := s.store()
	if err != nil {
		return nil, err
	}
	if _, err := st.Apply(model.Event{Type: model.EvHeartbeat, ID: id, Patch: patch}); err != nil {
		return nil, err
	}
	return s.entity(id)
}

func (s *server) toolDone(a map[string]any) (any, error) {
	id, err := argReqStr(a, "id")
	if err != nil {
		return nil, err
	}
	st, err := s.store()
	if err != nil {
		return nil, err
	}
	if _, err := st.Apply(model.Event{Type: model.EvUnregister, ID: id}); err != nil {
		return nil, err
	}
	return s.entity(id)
}

func (s *server) toolActive(map[string]any) (any, error) {
	st, err := s.store()
	if err != nil {
		return nil, err
	}
	snap, err := st.Snapshot()
	if err != nil {
		return nil, fmt.Errorf("cannot determine: %v", err)
	}
	return snap.Active, nil
}
