// Package model holds the wire/data types of the label-sync system.
// The authoritative description is docs/label-sync/CONTRACT.md.
package model

import (
	"bytes"
	"encoding/json"
	"reflect"
	"sort"
	"strings"
	"time"
)

// Entity kinds.
const (
	KindSession  = "session"
	KindAgent    = "agent"
	KindSubagent = "subagent"
	KindStream   = "stream"
	KindShell    = "shell"
	KindCommand  = "command"
	KindFlow     = "flow"
)

// Entity states.
const (
	StateRunning = "running"
	StateIdle    = "idle"
	StateDone    = "done"
	StateUnknown = "unknown"
)

// Event types.
const (
	EvRegister    = "register"
	EvUpdate      = "update"
	EvHeartbeat   = "heartbeat"
	EvUnregister  = "unregister"
	EvAliasSwitch = "alias_switch"
	EvReap        = "reap"
	EvReconcile   = "reconcile"
)

var kinds = map[string]bool{KindSession: true, KindAgent: true, KindSubagent: true,
	KindStream: true, KindShell: true, KindCommand: true, KindFlow: true}

var states = map[string]bool{StateRunning: true, StateIdle: true, StateDone: true, StateUnknown: true}

// ValidKind reports whether k is a contract entity kind.
func ValidKind(k string) bool { return kinds[k] }

// ValidState reports whether s is a contract entity state.
func ValidState(s string) bool { return states[s] }

// Entity is one labelled thing (session, agent, shell, ...).
// Label, State(rendered), Stale, Binding are COMPUTED at render time.
type Entity struct {
	ID           string    `json:"id"`
	Kind         string    `json:"kind"`
	ParentID     string    `json:"parent_id,omitempty"`
	SessionID    string    `json:"session_id,omitempty"`
	PID          int       `json:"pid,omitempty"`
	PIDStart     string    `json:"pid_start,omitempty"` // "<boot_id>:<starttime>" of PID at registration (pid-reuse guard)
	PIDNS        string    `json:"pid_ns,omitempty"`    // PID namespace of the registering process ("pid:[N]"); a writer in another namespace cannot judge PID
	Host         string    `json:"host,omitempty"`
	Cwd          string    `json:"cwd,omitempty"`
	Track        string    `json:"track,omitempty"`
	Branch       string    `json:"branch,omitempty"`
	Alias        string    `json:"alias,omitempty"`
	Model        string    `json:"model,omitempty"`
	Effort       string    `json:"effort,omitempty"`
	FollowActive bool      `json:"follow_active"`
	Source       string    `json:"source,omitempty"`
	StartedAt    time.Time `json:"started_at"`
	UpdatedAt    time.Time `json:"updated_at"`
	Label        string    `json:"label,omitempty"`
	State        string    `json:"state"`
	Stale        bool      `json:"stale,omitempty"`
	// Binding is COMPUTED: where alias/model/effort came from — "own",
	// "inherited:<ancestor id>", "active" or "unknown" (CONTRACT §4).
	Binding string `json:"binding,omitempty"`
	// Extra carries every JSON field this version does not know, so a
	// read/modify/write by this binary never drops a field a NEWER writer
	// added (re-review 3 finding 1: a pre-fix writer dropped pid_ns).
	Extra map[string]json.RawMessage `json:"-"`
}

type entityAlias Entity

// entityKeys are the JSON names this version knows (from the struct tags).
var entityKeys = func() map[string]bool {
	m := map[string]bool{}
	t := reflect.TypeOf(entityAlias{})
	for i := 0; i < t.NumField(); i++ {
		n := strings.Split(t.Field(i).Tag.Get("json"), ",")[0]
		if n != "" && n != "-" {
			m[n] = true
		}
	}
	return m
}()

// UnmarshalJSON decodes the known fields and keeps every other one in Extra.
func (e *Entity) UnmarshalJSON(b []byte) error {
	var a entityAlias
	if err := json.Unmarshal(b, &a); err != nil {
		return err
	}
	var all map[string]json.RawMessage
	if err := json.Unmarshal(b, &all); err != nil {
		return err
	}
	for k, v := range all {
		if !entityKeys[k] { // MUT:extrakeep
			if a.Extra == nil {
				a.Extra = map[string]json.RawMessage{}
			}
			a.Extra[k] = v
		}
	}
	*e = Entity(a)
	return nil
}

// MarshalJSON encodes the known fields, then the carried unknown ones
// (sorted, never overriding a known field).
func (e Entity) MarshalJSON() ([]byte, error) {
	b, err := json.Marshal(entityAlias(e))
	if err != nil || len(e.Extra) == 0 {
		return b, err
	}
	keys := make([]string, 0, len(e.Extra))
	for k := range e.Extra {
		if !entityKeys[k] && json.Valid(e.Extra[k]) {
			keys = append(keys, k)
		}
	}
	if len(keys) == 0 {
		return b, nil
	}
	sort.Strings(keys)
	var buf bytes.Buffer
	buf.Write(b[:len(b)-1])
	for _, k := range keys {
		kb, _ := json.Marshal(k)
		buf.WriteByte(',')
		buf.Write(kb)
		buf.WriteByte(':')
		buf.Write(e.Extra[k])
	}
	buf.WriteByte('}')
	return buf.Bytes(), nil
}

// Active is the operator's ACTIVE alias/model/effort context.
type Active struct {
	Alias      string    `json:"alias"`
	Model      string    `json:"model"`
	Effort     string    `json:"effort"`
	SwitchedAt time.Time `json:"switched_at"`
	Seq        uint64    `json:"seq"`
}

// Event is one line of events.jsonl.
type Event struct {
	Seq    uint64            `json:"seq"`
	TS     time.Time         `json:"ts"`
	Type   string            `json:"type"`
	ID     string            `json:"id,omitempty"`
	Entity *Entity           `json:"entity,omitempty"`
	Patch  map[string]string `json:"patch,omitempty"`
	Active *Active           `json:"active,omitempty"`
}

// Snapshot is snapshot.json: the rendered view consumers read.
type Snapshot struct {
	Seq         uint64    `json:"seq"`
	GeneratedAt time.Time `json:"generated_at"`
	Active      Active    `json:"active"`
	Entities    []Entity  `json:"entities"`
}
